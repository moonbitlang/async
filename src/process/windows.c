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
  return env_block;
}

struct EnvEntry {
  int32_t len;
  int32_t key_len;
};

static inline
struct EnvEntry resolve_env_entry(LPWCH block) {
  struct EnvEntry result = { 0, -1 };
  WCHAR c;
  while (c = block[result.len]) {
    if (result.key_len < 0 && c == L'=')
      result.key_len = result.len;
    ++result.len;
  }
  return result;
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_write_env_block(LPWCH dst, LPWCH env_block, int32_t base_offset) {
  LPWCH cursor = env_block;
  for (int dst_offset = base_offset;;) {
    struct EnvEntry entry = resolve_env_entry(cursor);

    // skip pseudo entries
    if (entry.key_len <= 0)
      goto skip_entry;

    // check if an duplicated entry already exists
    for (LPWCH cursor2 = dst; cursor2 - dst < base_offset;) {
      struct EnvEntry existing = resolve_env_entry(cursor2);
      if (
        entry.key_len == existing.key_len
        && CompareStringOrdinal(cursor2, existing.key_len, cursor, entry.key_len, TRUE)
           == CSTR_EQUAL
      ) {
        goto skip_entry;
      }

      cursor2 += existing.len + 1;
    }

    memcpy(dst + dst_offset, cursor, (entry.len + 1) * sizeof(WCHAR));
    dst_offset += entry.len + 1;

  skip_entry:
    cursor += entry.len + 1;
    if (*cursor == 0) {
      dst[dst_offset] = 0;
      break;
    }
  }
  FreeEnvironmentStringsW(env_block);
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_env_block_add_entry(
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

  // handle `NUL` in key or value to prevent injection
  int32_t entry_end = offset;
  while (env_block[entry_end])
    ++entry_end;
  // In case this is the last entry we ever written,
  // write the final NUL terminator.
  // If subsequent entry exists, they will overwrite the NUL here.
  env_block[entry_end + 1] = 0;
  return entry_end - offset < key_len ? offset : entry_end + 1;
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
