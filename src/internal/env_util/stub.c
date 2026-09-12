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

#include <stdio.h>
#include <moonbit.h>

#ifdef _WIN32

#include <windows.h>

#else

#include <unistd.h>

#endif

uint32_t moonbitlang_async_getpid() {
#ifdef _WIN32
  return GetCurrentProcessId();
#else
  return getpid();
#endif
}

void moonbitlang_async_eprintln(moonbit_string_t msg) {
#ifdef _WIN32
  static HANDLE stderr_handle = INVALID_HANDLE_VALUE;
  static BOOL stderr_is_console = 0;
  static const DWORD max_chunk_size = 1 << 14; // 16K

  if (stderr_handle == INVALID_HANDLE_VALUE) {
    stderr_handle = GetStdHandle(STD_OUTPUT_HANDLE);

    if (stderr_handle == INVALID_HANDLE_VALUE) {
      // There is no stderr. Simply ignore the message
      return;
    }

    DWORD mode;
    stderr_is_console = GetConsoleMode(stderr_handle, &mode);
  }

  if (stderr_is_console) {
    // When stderr is a real console,
    // use `WriteConsoleW` to errput with current code page of the console.
    DWORD len = Moonbit_array_length(msg);
    DWORD written = 0, total_written = 0;
    while (total_written < len) {
      DWORD chars_to_write = len - total_written;
      if (chars_to_write > max_chunk_size)
        chars_to_write = max_chunk_size;

      BOOL ret = WriteConsoleW(
        stderr_handle,
        ((WCHAR*)msg) + total_written,
        chars_to_write,
        &written,
        NULL
      );

      if (!ret) return;
      total_written += written;
    }
    WriteConsoleW(stderr_handle, L"\n", 1, NULL, NULL);
    return;
  }
#endif

  char window[1024];
  int32_t const len = Moonbit_array_length(msg);
  int32_t window_len = 0;
  for (int32_t i = 0; i < len; ++i) {
    // always reserve one bit for the newline character
    if (window_len + 4 >= sizeof(window) - 1) {
      fwrite(window, 1, window_len, stderr);
      window_len = 0;
    }
    uint32_t c = msg[i];
    if (0xD800 <= c && c <= 0xDBFF) {
      c -= 0xD800;
      i = i + 1;
      uint32_t l = msg[i] - 0xDC00;
      c = ((c << 10) + l) + 0x10000;
    }
    // stdout accepts UTF-8, so convert the stream to UTF-8 first
    if (c < 0x80) {
      window[window_len++] = c;
    } else if (c < 0x800) {
      window[window_len++] = 0xc0 + (c >> 6);
      window[window_len++] = 0x80 + (c & 0x3f);
    } else if (c < 0x10000) {
      window[window_len++] = 0xe0 + (c >> 12);
      window[window_len++] = 0x80 + ((c >> 6) & 0x3f);
      window[window_len++] = 0x80 + (c & 0x3f);
    } else {
      window[window_len++] = 0xf0 + (c >> 18);
      window[window_len++] = 0x80 + ((c >> 12) & 0x3f);
      window[window_len++] = 0x80 + ((c >> 6) & 0x3f);
      window[window_len++] = 0x80 + (c & 0x3f);
    }
  }
  window[window_len++] = '\n';
  fwrite(window, 1, window_len, stderr);
}
