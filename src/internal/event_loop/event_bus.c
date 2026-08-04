/*
 * Copyright 2025 International Digital Economy Academy
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <stdint.h>
#include <stdlib.h>
#include <moonbit.h>

void moonbit_panic(void);

#ifdef _WIN32

#ifndef _MSC_VER
#error "Currently only MSVC is supported on Windows"
#endif

#include <windows.h>

typedef HANDLE thread_id_t;
typedef DWORD  thread_worker_result_t;
#define THREAD_PROC_CALLING_CONVENTION WINAPI

typedef CRITICAL_SECTION   mutex_t;
typedef CONDITION_VARIABLE cond_t;

#define mutex_init(mutex)    InitializeCriticalSection(mutex)
#define mutex_destroy(mutex) (void)0
#define mutex_trylock(mutex) TryEnterCriticalSection(mutex)
#define mutex_lock(mutex)    EnterCriticalSection(mutex)
#define mutex_unlock(mutex)  LeaveCriticalSection(mutex)

#define cond_init(cond)    InitializeConditionVariable(cond)
#define cond_destroy(cond) (void)0
#define cond_signal(cond)  WakeConditionVariable(cond)

static inline
int32_t cond_wait(cond_t *cond, mutex_t *mutex) {
  return SleepConditionVariableCS(cond, mutex, INFINITE) ? 0 : -1;
}

// #ifdef _WIN32
#else

#include <pthread.h>
#include <signal.h>
#include <errno.h>

typedef int HANDLE;
#define GetLastError() errno
#define SetLastError(err) errno = (err)

typedef pthread_t  thread_id_t;
typedef void      *thread_worker_result_t;
#define THREAD_PROC_CALLING_CONVENTION

typedef pthread_mutex_t mutex_t;
typedef pthread_cond_t  cond_t;

#define mutex_init(mutex)    pthread_mutex_init(mutex, 0)
#define mutex_destroy(mutex) pthread_mutex_destroy(mutex)
#define mutex_lock(mutex)    pthread_mutex_lock(mutex)
#define mutex_unlock(mutex)  pthread_mutex_unlock(mutex)

static inline
int32_t mutex_trylock(mutex_t *mutex) {
  int ret = pthread_mutex_trylock(mutex);
  if (ret == EBUSY)
    return 0;
  else if (!ret)
    return 1;

  errno = ret;
  return -1;
}

#define cond_init(cond)    pthread_cond_init(cond, 0)
#define cond_destroy(cond) pthread_cond_destroy(cond)
#define cond_signal(cond)  pthread_cond_signal(cond)

static
int32_t cond_wait(cond_t *cond, mutex_t *mutex) {
  int ret = pthread_cond_wait(cond, mutex);
  if (!ret)
    return 0;

#ifdef __MACH__
  // There's a bug in the MacOS's `pthread_cond_wait`,
  // see https://github.com/graphia-app/graphia/issues/33
  // We know the arguments must be valid here,
  // so treat `EINVAL` as spurious wakeup here to workaround
  if (ret == EINVAL)
    return 0;
#endif

  errno = ret;
  return -1;
}

#endif // #ifndef _WIN32

// defined in `epoll.c`/`kqueue.c`/`iocp.c`
int32_t moonbitlang_async_event_bus_wait(HANDLE bus, int32_t timeout);

struct EventBusWaiter {
  thread_id_t thread_id;
  HANDLE event_bus;
  void (*wakeup_callback)(void);

  int32_t cancelled;
  int32_t error;

  mutex_t lock;
  cond_t waker;

  // The following fields, together with the static event buffer
  // in `epoll.c`/`kqueue.c`/`iocp.c`, should be protected by
  // `lock` above.
  int32_t number_of_events;
};

static
thread_worker_result_t THREAD_PROC_CALLING_CONVENTION waiter_loop(void *data) {
  struct EventBusWaiter *waiter = (struct EventBusWaiter*)data;

  mutex_lock(&waiter->lock);

  for (;;) {
    // When control flow reaches here:
    // - `waiter->lock` should have been acquired
    // - `waiter->number_of_events` must be zero
    // - `waiter->state` must be `SUSPENDED`
    waiter->number_of_events = moonbitlang_async_event_bus_wait(waiter->event_bus, -1); 
    mutex_unlock(&waiter->lock);

    if (waiter->number_of_events < 0) {
      waiter->error = GetLastError();
      goto exit;
    }

    if (waiter->number_of_events == 0)
      continue;

    // `waiter->number_of_events > 0` must hold here,
    // when we wake the main thread and suspend the waiter

    waiter->wakeup_callback();

    mutex_lock(&waiter->lock);
    while (waiter->number_of_events > 0) {
      if (cond_wait(&waiter->waker, &waiter->lock) < 0) {
        mutex_unlock(&waiter->lock);
        waiter->error = GetLastError();
        goto exit;
      }
      if (waiter->cancelled)
        goto exit;
    }
  }

exit:
  // `waiter->lock` must be released here
  return 0;
}

MOONBIT_FFI_EXPORT
struct EventBusWaiter *moonbitlang_async_spawn_event_bus_waiter(
  HANDLE bus,
  void (*wakeup_callback)(void)
) {
  struct EventBusWaiter *waiter = (struct EventBusWaiter*)malloc(sizeof(struct EventBusWaiter));
  waiter->event_bus = bus;
  waiter->wakeup_callback = wakeup_callback;

  mutex_init(&waiter->lock);
  cond_init(&waiter->waker);

  waiter->number_of_events = 0;
  waiter->cancelled = 0;
  waiter->error = 0;

#ifdef _WIN32

  waiter->thread_id = CreateThread(NULL, 512, &waiter_loop, waiter, 0, 0);

// #ifdef _WIN32
#else

  pthread_attr_t attr;
  pthread_attr_init(&attr);
#ifdef __ANDROID__
  pthread_attr_setstacksize(&attr, 64 * 1024);
#else
  pthread_attr_setstacksize(&attr, 512);
#endif

  sigset_t curr_sigmask, waiter_sigmask;
  sigfillset(&waiter_sigmask);
  sigdelset(&waiter_sigmask, SIGUSR2);
  pthread_sigmask(SIG_SETMASK, &waiter_sigmask, &curr_sigmask);

  pthread_create(&waiter->thread_id, &attr, &waiter_loop, waiter);

  pthread_sigmask(SIG_SETMASK, &curr_sigmask, 0);
  pthread_attr_destroy(&attr);

#endif

  return waiter;
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_terminate_event_bus_waiter(struct EventBusWaiter *waiter) {
  waiter->cancelled = 1;
  int ret = mutex_trylock(&waiter->lock);
  if (ret < 0)
    // Something unrecoverable happened, force-kill the program
    moonbit_panic();

  if (!ret) {
#ifdef _WIN32
    PostQueuedCompletionStatus(waiter->event_bus, 0, 0, 0);
#else
    pthread_kill(waiter->thread_id, SIGUSR2);
#endif

    mutex_lock(&waiter->lock);
  }

  // At this point `waiter->lock` must be acquired.
  // In case the waiter is in suspended state, wake it up
  cond_signal(&waiter->waker);
  mutex_unlock(&waiter->lock);

  pthread_join(waiter->thread_id, 0);

  mutex_destroy(&waiter->lock);
  cond_destroy(&waiter->waker);

  free(waiter);
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_event_bus_waiter_get_events(struct EventBusWaiter *waiter) {
  int ret = mutex_trylock(&waiter->lock);
  if (ret < 0)
    return -1;

  if (!ret)
    return 0;

  if (waiter->error) {
    mutex_unlock(&waiter->lock);
    SetLastError(waiter->error);
    return -1;
  }

  if (waiter->number_of_events == 0)
    // This can happen on initialization
    mutex_unlock(&waiter->lock);

  return waiter->number_of_events;
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_wake_event_bus_waiter(struct EventBusWaiter *waiter) {
  // `waiter->lock` should be acquired here
  waiter->number_of_events = 0;
  cond_signal(&waiter->waker);
  mutex_unlock(&waiter->lock);
}
