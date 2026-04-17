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

#else

#include <signal.h>
#include <string.h>

#endif

#ifdef _WIN32

#else // #ifdef _WIN32

MOONBIT_FFI_EXPORT
int moonbitlang_async_get_signal_by_name(const char *name) {
  if (0 == strcmp(name, "SIGINT")) {
    return SIGINT;
  } else if (0 == strcmp(name, "SIGTERM")) {
    return SIGTERM;
  } else if (0 == strcmp(name, "SIGHUP")) {
    return SIGHUP;
  } else {
    return -1;
  }
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_set_global_cancellation_signals(int *all_signals, int *signals) {
  sigset_t set;
  pthread_sigmask(SIG_SETMASK, 0, &set);
  for (int i = 0; i < Moonbit_array_length(all_signals); ++i) {
    if (all_signals[i] < 0) continue;
    sigdelset(&set, all_signals[i]);
  }
  for (int i = 0; i < Moonbit_array_length(signals); ++i) {
    if (signals[i] < 0) continue;
    sigaddset(&set, signals[i]);
  }
  pthread_sigmask(SIG_SETMASK, &set, 0);
}

#endif // #ifndef _WIN32
