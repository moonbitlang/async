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

typedef volatile int32_t atomic_int32_t;

typedef HANDLE thread_id_t;
typedef DWORD  thread_worker_result_t;
#define THREAD_PROC_CALLING_CONVENTION WINAPI

typedef CRITICAL_SECTION   mutex_t;
typedef CONDITION_VARIABLE cond_t;

#define mutex_init(mutex)    InitializeCriticalSection(mutex)
#define mutex_destroy(mutex) (void)0
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

#include <stdatomic.h>
#include <unistd.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <errno.h>
#include <poll.h>

typedef _Atomic int32_t atomic_int32_t;

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

#ifndef _WIN32
  int cancel_pipe[2];
#endif

  atomic_int32_t cancelled;
  int32_t error;

  mutex_t lock;
  cond_t waker;

  /* `status` should be protected by `lock` above.
   
     On Unix systems, instead of doing `epoll_wait`/`kevent` in the waiter thread directly,
     we only wait for the readiness of the underlying `epoll`/`kqueue` in the waiter.
     The actual retrieval of events are still performed in the main thread,
     via a zero-timeout `epoll_wait`/`kevent` call.

     The reason for this is that performing wait in an alternative thread introduce
     various kinds of race condition. For example, registering a unconnected socket
     may produce stale `EPOLLOUT | EPOLLHUP` event. Usually, a subsequent `connect`
     call will remove that stale event, and the final `epoll_wait` will not see it.
     However, if `epoll_wait` is performed in a dedicated thread, this kind of stale
     event may accidentally get captured.

     Hence, on Unix systems, `status` is merely a boolean hint
     indicating whether there is any event.
     while the static `epoll`/`kqueue` event buffer is exclusively owned by the main thread.

     On Windows, we perform `GetQueuedCompletionStatusEx` in the waiter thread directly,
     because IOCP completion packets are associated with invidual IO operations,
     and hence has no stale event issue. Another reason is IOCP does not support peeking,
     so we cannot use the same approach as Unix-like systems.

     On Windows, `status` is the number of event is retrieved,
     and the static buffer should also be protected by `lock` above.
   */
  atomic_int32_t status;
};

static
thread_worker_result_t THREAD_PROC_CALLING_CONVENTION waiter_loop(void *data) {
  struct EventBusWaiter *waiter = (struct EventBusWaiter*)data;

  mutex_lock(&waiter->lock);

  while (!waiter->cancelled) {
    // When control flow reaches here:
    // - `waiter->lock` should have been acquired
    // - `waiter->status` must be zero
#ifdef _WIN32
    waiter->status = moonbitlang_async_event_bus_wait(waiter->event_bus, -1); 

    if (waiter->status == 0)
      continue;

    if (waiter->status < 0) {
      waiter->error = GetLastError();
      goto exit;
    }
#else
    struct pollfd pfds[] = {
      { waiter->event_bus, POLLIN, 0 },
      { waiter->cancel_pipe[0], POLLIN, 0 }
    };
    int ret = poll(pfds, 2, -1);

    if (ret < 0) {
      waiter->error = errno;
      goto exit;
    }

    waiter->status = pfds[0].revents & POLLIN;
    if (!waiter->status)
      continue;
#endif

    // `waiter->status` must be non-zero here,
    // when we wake the main thread and suspend the waiter

    waiter->wakeup_callback();

    while (waiter->status && !waiter->cancelled) {
      if (cond_wait(&waiter->waker, &waiter->lock) < 0) {
        waiter->error = GetLastError();
        goto exit;
      }
    }
  }


exit:
  mutex_unlock(&waiter->lock);
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

#ifndef _WIN32
  if (pipe(waiter->cancel_pipe) < 0)
    goto error;

  for (int i = 0; i < 2; ++i) {
    int fd = waiter->cancel_pipe[i];
    int flags = fcntl(fd, F_GETFD);
    if (flags < 0)
      goto error_with_pipe;

    if (!(flags & FD_CLOEXEC) && fcntl(fd, F_SETFD, flags | FD_CLOEXEC) < 0)
      goto error_with_pipe;
  }
#endif

  mutex_init(&waiter->lock);
  cond_init(&waiter->waker);

  waiter->status = 0;
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
  pthread_sigmask(SIG_SETMASK, &waiter_sigmask, &curr_sigmask);

  pthread_create(&waiter->thread_id, &attr, &waiter_loop, waiter);

  pthread_sigmask(SIG_SETMASK, &curr_sigmask, 0);
  pthread_attr_destroy(&attr);

#endif

  return waiter;

#ifndef _WIN32
error_with_pipe:
  close(waiter->cancel_pipe[0]);
  close(waiter->cancel_pipe[1]);
#endif

error:
  free(waiter);
  return 0;
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_terminate_event_bus_waiter(struct EventBusWaiter *waiter) {
  waiter->cancelled = 1;
  if (!waiter->status) {
    /* If the waiter is currently blocked, try to wake it up.
       Note that the code here is not atomic, so the following sequence is possible:
      
       - main thread see `waiter->status == 0`
       - waiter woken and set `waiter->status` to a non-zero value
       - main thread perform cancellation operation below

       But this sequence is fine, because the cancellation operation below
       would be just no-op if the waiter is not currently blocked.
     */
#ifdef _WIN32
    PostQueuedCompletionStatus(waiter->event_bus, 0, 0, 0);
#else
    int32_t data = 0;
    while (write(waiter->cancel_pipe[1], &data, sizeof(data)) < 0)
      if (errno != EINTR)
        // unrecoverable error
        moonbit_panic();
#endif
  }

  // In case the waiter is suspended, wake it up.
  mutex_lock(&waiter->lock);
  cond_signal(&waiter->waker);
  mutex_unlock(&waiter->lock);

#ifdef _WIN32
  WaitForSingleObject(waiter->thread_id, INFINITE);
#else
  pthread_join(waiter->thread_id, 0);
#endif

  mutex_destroy(&waiter->lock);
  cond_destroy(&waiter->waker);

#ifndef _WIN32
  close(waiter->cancel_pipe[0]);
  close(waiter->cancel_pipe[1]);
#endif

  free(waiter);
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_wake_event_bus_waiter(struct EventBusWaiter *waiter) {
  // `waiter->lock` should be acquired here
  waiter->status = 0;
  cond_signal(&waiter->waker);
  mutex_unlock(&waiter->lock);
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_event_bus_waiter_get_events(struct EventBusWaiter *waiter) {
  if (!waiter->status)
    return 0;

  // Only the main thread will turn `status` from non-zero to zero,
  // So `waiter->status!= 0` will not get violated
  // in the window after the previous check and before acquiring the lock.
  mutex_lock(&waiter->lock);

  if (waiter->error) {
    mutex_unlock(&waiter->lock);
    SetLastError(waiter->error);
    return -1;
  }

#ifdef _WIN32
  return waiter->status;
#else
  int32_t ret = moonbitlang_async_event_bus_wait(waiter->event_bus, 0);

  // This may happen when there is stale event that appeared and then disappeared
  // or some extra error happened after the waiter is woken.
  // Our contract for `waiter_get_events` is that if it return zero or negative value,
  // `waiter->lock` should be unlocked in the main thread,
  // and the wait thread should keep going.
  if (ret <= 0)
    moonbitlang_async_wake_event_bus_waiter(waiter); 

  if (ret < 0 && errno == EINTR)
    ret = 0;

  return ret;
#endif
}
