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
#include <stdint.h>
#include <stdlib.h>
#include <moonbit.h>

#ifdef _WIN32

#include <windows.h>

#else

#include <stdatomic.h>
#include <time.h>
#include <unistd.h>
#ifdef __linux__
#include <sys/syscall.h>
#endif

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

#ifndef _WIN32

static _Atomic unsigned long long trace_seq = 0;
static _Atomic int trace_enabled_cache = 0;

static int trace_enabled(void) {
  int state = atomic_load_explicit(&trace_enabled_cache, memory_order_relaxed);
  if (state == 0) {
    state = getenv("MOONBIT_ASYNC_PIDFD_TRACE") ? 2 : 1;
    atomic_store_explicit(&trace_enabled_cache, state, memory_order_relaxed);
  }
  return state == 2;
}

static const char *trace_event_name(int32_t event) {
  switch (event) {
  case 1: return "mbt.wait_read.start";
  case 2: return "mbt.wait_read.resume";
  case 3: return "mbt.handle_read_event";
  case 4: return "mbt.handle_write_event";
  case 10: return "mbt.read_from_process.close";
  case 11: return "mbt.write_to_process.close";
  case 12: return "mbt.process_input.close";
  case 13: return "mbt.process_output.close";
  case 20: return "mbt.spawn.wait_task.start";
  case 21: return "mbt.spawn.wait_task.cancelled";
  case 22: return "mbt.spawn.cancel_handler.spawn";
  case 23: return "mbt.spawn.cleanup_wait.start";
  case 24: return "mbt.spawn.cleanup_wait.done";
  case 25: return "mbt.spawn.wait_task.done";
  default: return "mbt.unknown";
  }
}

void moonbitlang_async_trace_log_c(
  const char *event,
  long long a,
  long long b,
  long long c,
  long long d
) {
  if (!trace_enabled())
    return;

  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
#ifdef __linux__
  long tid = syscall(SYS_gettid);
#else
  long tid = 0;
#endif
  unsigned long long seq =
    atomic_fetch_add_explicit(&trace_seq, 1, memory_order_relaxed) + 1;

  fprintf(
    stderr,
    "moonbitlang/async-trace seq=%llu t=%lld.%09ld pid=%ld tid=%ld event=%s a=%lld b=%lld c=%lld d=%lld\n",
    seq,
    (long long)ts.tv_sec,
    ts.tv_nsec,
    (long)getpid(),
    tid,
    event,
    a,
    b,
    c,
    d
  );
}

void moonbitlang_async_timing_log_c(
  const char *event,
  long long a,
  long long b,
  long long c,
  long long d
) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
#ifdef __linux__
  long tid = syscall(SYS_gettid);
#else
  long tid = 0;
#endif
  unsigned long long seq =
    atomic_fetch_add_explicit(&trace_seq, 1, memory_order_relaxed) + 1;

  fprintf(
    stderr,
    "moonbitlang/async-timing seq=%llu t=%lld.%09ld pid=%ld tid=%ld event=%s a=%lld b=%lld c=%lld d=%lld\n",
    seq,
    (long long)ts.tv_sec,
    ts.tv_nsec,
    (long)getpid(),
    tid,
    event,
    a,
    b,
    c,
    d
  );
}

void moonbitlang_async_trace_log(
  int32_t event,
  int32_t a,
  int32_t b,
  int32_t c,
  int32_t d
) {
  moonbitlang_async_trace_log_c(trace_event_name(event), a, b, c, d);
}

#else

void moonbitlang_async_trace_log(
  int32_t event,
  int32_t a,
  int32_t b,
  int32_t c,
  int32_t d
) {
  (void)event;
  (void)a;
  (void)b;
  (void)c;
  (void)d;
}

void moonbitlang_async_timing_log_c(
  const char *event,
  long long a,
  long long b,
  long long c,
  long long d
) {
  (void)event;
  (void)a;
  (void)b;
  (void)c;
  (void)d;
}

#endif
