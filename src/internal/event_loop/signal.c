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

#include "moonbit.h"

#ifdef _WIN32

#include <windows.h>
#include <stdio.h>

#else

#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <pthread.h>

_Noreturn
void moonbit_panic();

#endif

enum SignalCode {
  SIGINT_CODE = 0,
  SIGTERM_CODE = 1,
  SIGHUP_CODE = 2,
  SIGBREAK_CODE = 3
};

void moonbitlang_async_notify_event_loop(int32_t data);

#ifdef _WIN32

MOONBIT_FFI_EXPORT
int moonbitlang_async_get_signal_by_index(int32_t code) {
  switch (code) {
    case SIGINT_CODE: return CTRL_C_EVENT;
    case SIGBREAK_CODE: return CTRL_BREAK_EVENT;
    case SIGHUP_CODE: return CTRL_CLOSE_EVENT;
    default: return -1;
  }
}

// The range of console control events is pretty small
// according to https://learn.microsoft.com/en-us/windows/console/handlerroutine,
// and a set of console contron events can easily fix into a single byte.
// So there is no need for atomic integer here
static
int interested_console_ctrl_event = 0;

static
BOOL WINAPI console_control_handler(DWORD ctrl_type) {
  if (interested_console_ctrl_event & (1 << ctrl_type)) {
    moonbitlang_async_notify_event_loop(ctrl_type | (1 << 31));
    return TRUE;
  } else {
    return FALSE;
  }
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_set_global_cancellation_signals(
  int32_t *all_signals,
  int32_t all_signals_length,
  int32_t *signals,
  int32_t signals_length
) {
  int new_mask = 0;
  for (int i = 0; i < signals_length; ++i) {
    if (signals[i] < 0) continue;
    new_mask |= 1 << signals[i];
  }
  interested_console_ctrl_event = new_mask;
}

MOONBIT_FFI_EXPORT
int moonbitlang_async_get_sigwinch() {
  return -1;
}

MOONBIT_FFI_EXPORT
int moonbitlang_async_set_console_control_handler(int32_t add) {
  return SetConsoleCtrlHandler(console_control_handler, add);
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_terminate_process_by_signal(int32_t sig) {
  // flush stdio buffers used by `println` etc.
  fflush(0);

  ExitProcess(STATUS_CONTROL_C_EXIT);
}

#else // #ifdef _WIN32

MOONBIT_FFI_EXPORT
int moonbitlang_async_get_signal_by_index(int32_t code) {
  switch (code) {
    case SIGINT_CODE: return SIGINT;
    case SIGTERM_CODE: return SIGTERM;
    case SIGHUP_CODE: return SIGHUP;
    default: return -1;
  }
}

MOONBIT_FFI_EXPORT
int moonbitlang_async_get_sigwinch() {
  return SIGWINCH;
}

static
struct {
  int32_t initialized;
  int32_t started;
  pthread_t handler;

  pthread_mutex_t lock;

  // the following should be protected by `lock`

  // the set of currently active cancellation signals + `SIGWINCH` + `SIGUSR2`.
  sigset_t interested_signals;
  int32_t cancelled;

  // the action of `SIGWINCH` before `start_signal_handler`
  struct sigaction prev_sigwinch_action;
} signal_config = { 0, 0 };

// On macOS, a signal ignored by default, such as `SIGWINCH`, is discarded
// when generated, even while blocked, unless it has a handler.
// The handler never runs: `SIGWINCH` is blocked and taken by `sigwait`.
static
void sigwinch_handler(int sig) {
  (void)sig;
}

static
void *sigwait_thread_worker(void *data) {
  sigset_t wait_set;

  // Block every signal in this thread: `sigwait` only requires the awaited
  // signals to be blocked, and leaving the others unblocked would let the
  // kernel deliver a process-directed signal to this thread and run its
  // default action instead.
  sigset_t all_signals;
  sigfillset(&all_signals);
  pthread_sigmask(SIG_SETMASK, &all_signals, 0);

  while (1) {
    pthread_mutex_lock(&signal_config.lock);
    memcpy(&wait_set, &signal_config.interested_signals, sizeof(sigset_t));
    pthread_mutex_unlock(&signal_config.lock);

    int sig = 0;
    errno = 0;
    int err = sigwait(&wait_set, &sig);
    int sigwait_errno = errno;

    if (err > 0)
      break;

    pthread_mutex_lock(&signal_config.lock);

    int32_t cancelled = signal_config.cancelled;
    int32_t is_interested =
      sig && sig != SIGUSR2 && sigismember(&signal_config.interested_signals, sig); 

    pthread_mutex_unlock(&signal_config.lock);

    if (cancelled)
      break;

    if (is_interested) {
      moonbitlang_async_notify_event_loop(sig | (1 << 31)); 
      continue;
    }

    // It seems that on MacOS, it is possible for `sigwait` to
    // silently return `0` without returning a signal,
    // and set `errno` to `EINTR`.
    // Handle this case here by retrying.
    if (sigwait_errno && sigwait_errno != EINTR) {
      break;
    }
  }
  return 0;
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_set_global_cancellation_signals(
  int32_t *all_signals,
  int32_t all_signals_length,
  int32_t *signals,
  int32_t signals_length
) {
  if (!signal_config.initialized) {
    signal_config.initialized = 1;
    signal_config.cancelled = 0;
    pthread_mutex_init(&signal_config.lock, 0);
  }

  sigset_t signals_to_block;
  pthread_sigmask(SIG_SETMASK, 0, &signals_to_block);

  pthread_mutex_lock(&signal_config.lock);
  sigemptyset(&signal_config.interested_signals);

  for (int i = 0; i < all_signals_length; ++i) {
    if (all_signals[i] < 0) continue;
    sigdelset(&signals_to_block, all_signals[i]);
  }
  for (int i = 0; i < signals_length; ++i) {
    if (signals[i] < 0) continue;
    sigaddset(&signals_to_block, signals[i]);
    sigaddset(&signal_config.interested_signals, signals[i]);
  }

  sigaddset(&signal_config.interested_signals, SIGUSR2);
  pthread_mutex_unlock(&signal_config.lock);

  pthread_sigmask(SIG_SETMASK, &signals_to_block, 0);

  if (signal_config.started) {
    // wake the `sigwait` thread for config update
    pthread_kill(signal_config.handler, SIGUSR2);
  }
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_start_signal_handler() {
  if (!signal_config.initialized || signal_config.started) {
    // should be initialized by `set_global_cancellation_signals` before calling this
    moonbit_panic();
  }

  signal_config.started = 1;

  sigaction(SIGWINCH, NULL, &signal_config.prev_sigwinch_action);
  if (signal_config.prev_sigwinch_action.sa_handler == SIG_DFL) {
    struct sigaction act;
    memset(&act, 0, sizeof(act));
    act.sa_handler = sigwinch_handler;
    sigemptyset(&act.sa_mask);
    sigaction(SIGWINCH, &act, NULL);
  }

  pthread_attr_t attr;
  pthread_attr_init(&attr);
#ifdef __ANDROID__
  pthread_attr_setstacksize(&attr, 64 * 1024);
#else
  pthread_attr_setstacksize(&attr, 512);
#endif

  sigset_t prev_mask;
  pthread_sigmask(SIG_BLOCK, &signal_config.interested_signals, &prev_mask);

  pthread_create(&signal_config.handler, &attr, &sigwait_thread_worker, 0);

  pthread_sigmask(SIG_SETMASK, &prev_mask, 0);

  pthread_attr_destroy(&attr);
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_terminate_signal_handler() {
  if (!signal_config.started)
    return;

  pthread_mutex_lock(&signal_config.lock);
  signal_config.cancelled = 1;
  pthread_mutex_unlock(&signal_config.lock);

  pthread_kill(signal_config.handler, SIGUSR2);
  pthread_join(signal_config.handler, 0);

  sigaction(SIGWINCH, &signal_config.prev_sigwinch_action, NULL);

  pthread_mutex_destroy(&signal_config.lock);
  signal_config.initialized = 0;
  signal_config.started = 0;
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_terminate_process_by_signal(int32_t sig) {
  sigset_t sigset;
  sigemptyset(&sigset);
  sigaddset(&sigset, sig);
  pthread_sigmask(SIG_UNBLOCK, &sigset, 0);

  // flush stdio buffers used by `println` etc.
  fflush(0);

  raise(sig);
}

#endif // #ifndef _WIN32
