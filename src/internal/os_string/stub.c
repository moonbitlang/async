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

#include <string.h>
#include <wchar.h>
#include <moonbit.h>

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_c_buffer_fill_string(
  wchar_t *str,
  int32_t len,
  moonbit_string_t out,
  int32_t out_len
) {
  size_t bytes = len == -1 ? wcslen(str) * sizeof(wchar_t) : len;
  int32_t actual_len = bytes / 2;
  if (actual_len <= out_len) {
    memcpy(out, str, bytes);
  }
  return actual_len;
}
