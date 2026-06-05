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

#include <moonbit.h>

#ifdef _WIN32

#include <windows.h>

LPWCH env_block = NULL;
LPWCH env_ptr = NULL;

MOONBIT_FFI_EXPORT
void init_env() {
  if (env_block)
    FreeEnvironmentStringsW(env_block);
  env_block = GetEnvironmentStringsW();
  env_ptr = env_block;
}

MOONBIT_FFI_EXPORT
void free_env() {
  if (env_block)
    FreeEnvironmentStringsW(env_block);
  env_block = NULL;
  env_ptr = NULL;
}

MOONBIT_FFI_EXPORT
int32_t next_entry_fill(moonbit_string_t out, int32_t out_len) {
  if (!env_ptr)
    return 0;

  int len = wcslen(env_ptr);
  if (len == 0)
    return 0;

  if (len <= out_len) {
    memcpy(out, env_ptr, len * sizeof(WCHAR));
    env_ptr += len + 1;
  }
  return len;
}

#else

#include <string.h>

extern char **environ;
char **cursor = 0;

MOONBIT_FFI_EXPORT
void init_env() {
  cursor = environ;
}

MOONBIT_FFI_EXPORT
void free_env() {}

MOONBIT_FFI_EXPORT
int32_t next_entry_fill(moonbit_bytes_t out, int32_t out_len) {
  if (cursor == 0 || *cursor == 0)
    return 0;

  int len = strlen(*cursor);
  if (len == 0)
    return 0;

  if (len <= out_len) {
    memcpy(out, *cursor, len);
    cursor += 1;
  }
  return len;
}

#endif
