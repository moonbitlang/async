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

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/wait.h>
#endif

#include <moonbit.h>

#ifdef _WIN32

MOONBIT_FFI_EXPORT
int moonbitlang_async_get_process_result(HANDLE handle, DWORD *out) {
  int result = GetExitCodeProcess(handle, out) ? 0 : -1;
  return result;
}

MOONBIT_FFI_EXPORT
HANDLE moonbitlang_async_open_pid_handle(DWORD pid) {
  return OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
}

#else

MOONBIT_FFI_EXPORT
int moonbitlang_async_get_process_result(pid_t pid, int *out) {
  int wstatus;
  int ret = waitpid(pid, &wstatus, 0);
  if (ret > 0) {
    *out = WEXITSTATUS(wstatus);
    return 0;
  } else {
    return -1;
  }
}

#endif
