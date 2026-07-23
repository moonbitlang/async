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

MOONBIT_FFI_EXPORT
LPWCH moonbitlang_async_get_curr_env() {
  LPWCH env = GetEnvironmentStringsW();
  return env ? env : L"\0\0";
}

// return the size of the env block, in number of `WCHAR`,
// excluding the final trailing NUL
MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_env_block_length(LPWCH env_block) {
  LPWCH cursor = env_block;
  int len = 0;
  for (;;) {
    int block_len = 0;
    while (cursor[block_len])
      ++block_len;

    // skip pseudo entries
    if (*cursor != L'=')
      len += block_len + 1;

    cursor += block_len + 1;
    if (*cursor == 0)
      break;
  }
  return len;
}

MOONBIT_FFI_EXPORT
LPWCH moonbitlang_async_allocate_env_block(int32_t size) {
  LPWCH env_block = (LPWCH)malloc((size + 1) * sizeof(WCHAR));
  env_block[size] = 0;
  return env_block;
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_write_env_block(LPWCH dst, LPWCH env_block) {
  LPWCH cursor = env_block;
  for (int dst_offset = 0;;) {
    int32_t block_len = 0;
    while (cursor[block_len])
      ++block_len;

    // skip pseudo entries
    if (*cursor != L'=') {
      memcpy(dst + dst_offset, cursor, (block_len + 1) * sizeof(WCHAR));
      dst_offset += block_len + 1;
    }

    cursor += block_len + 1;
    if (*cursor == 0)
      break;
  }
  FreeEnvironmentStringsW(env_block);
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_env_block_add_entry(
  LPWCH env_block,
  int32_t offset,
  moonbit_string_t key,
  int32_t key_len,
  moonbit_string_t value,
  int32_t value_len
) {
  memcpy(env_block + offset, key, key_len * sizeof(WCHAR));
  env_block[offset + key_len] = L'=';
  memcpy(env_block + offset + key_len + 1, value, value_len * sizeof(WCHAR));
  env_block[offset + key_len + 1 + value_len] = 0;
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
