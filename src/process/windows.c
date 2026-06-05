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
#include <moonbit.h>

int32_t moonbitlang_async_curr_env_fill(moonbit_string_t out, int32_t out_len) {
  LPWCH env_block = GetEnvironmentStringsW();
  if (!env_block)
    return 0;

  int len = 0;
  while (env_block[len] != 0 || env_block[len + 1] != 0) {
    ++len;
  }
  len += 2;
  if (len <= out_len) {
    memcpy(out, env_block, len * sizeof(WCHAR));
  }
  FreeEnvironmentStringsW(env_block);
  return len;
}

void moonbitlang_async_terminate_process(DWORD pid, int signal) {
  GenerateConsoleCtrlEvent(signal, pid);
}

void moonbitlang_async_kill_process(DWORD pid) {
  HANDLE handle = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
  if (handle == INVALID_HANDLE_VALUE)
    return;

  TerminateProcess(handle, 1);
  CloseHandle(handle);
}

#endif
