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

#endif

enum SignalCode {
  SIGINT_CODE = 0,
  SIGTERM_CODE = 1,
  SIGHUP_CODE = 2,
  SIGBREAK_CODE = 3
};

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
extern int interested_console_ctrl_event;

// the actual console control handler is in `thread_pool.c`,
// because it need to refer to the event loop's IO completion port
BOOL WINAPI moonbitlang_async_console_control_handler(DWORD ctrl_type);

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
int moonbitlang_async_set_console_control_handler(int32_t add) {
  return SetConsoleCtrlHandler(moonbitlang_async_console_control_handler, add);
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
void moonbitlang_async_set_global_cancellation_signals(
  int32_t *all_signals,
  int32_t all_signals_length,
  int32_t *signals,
  int32_t signals_length
) {
  sigset_t set;
  pthread_sigmask(SIG_SETMASK, 0, &set);
  for (int i = 0; i < all_signals_length; ++i) {
    if (all_signals[i] < 0) continue;
    sigdelset(&set, all_signals[i]);
  }
  for (int i = 0; i < signals_length; ++i) {
    if (signals[i] < 0) continue;
    sigaddset(&set, signals[i]);
  }
  pthread_sigmask(SIG_SETMASK, &set, 0);
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
