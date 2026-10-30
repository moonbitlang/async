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

#include <stdint.h>
#include <moonbit.h>

// Only Windows needs a job: on Unix the terminal is read through the event bus
#ifdef _WIN32

#include <windows.h>
#include <string.h>

// MoonBit array data follows its object header in a heap allocation.
_Static_assert(
  _Alignof(struct moonbit_object) >= _Alignof(INPUT_RECORD),
  "MoonBit array data must be aligned for INPUT_RECORD"
);

struct worker;
struct worker *moonbitlang_async_get_current_worker(void);
int32_t moonbitlang_async_enter_cancellable_region(struct worker *worker);
void moonbitlang_async_leave_cancellable_region(struct worker *worker);
void *moonbitlang_async_make_job(
  int32_t size,
  void (*free)(void*),
  int32_t (*worker)(void*, int32_t*),
  int32_t (*cancel_handler)(void*)
);

#define MAKE_JOB(name, cancel_handler) (struct name##_job*)moonbitlang_async_make_job(\
  sizeof(struct name##_job),\
  (void (*)(void*))free_##name##_job,\
  (int32_t (*)(void*, int32_t*)) name##_job_worker,\
  (int32_t (*)(void*))cancel_handler\
)

enum {
  TTY_READ_RESIZED = -1,
};

struct read_console_input_job {
  HANDLE input;
  HANDLE cancel;
  uint16_t *buf;
  int32_t len;
  // set when input is returned and a resize was read with it
  int32_t resized;
};

static
void free_read_console_input_job(struct read_console_input_job *job) {
  if (job->cancel)
    CloseHandle(job->cancel);
  moonbit_decref(job->buf);
}

static
int32_t tty_records_to_text(
  uint16_t *buf,
  DWORD count,
  int32_t *resized
) {
  int32_t pos = 0;
  for (DWORD i = 0; i < count; ++i) {
    // Copy before compacting in place, without aliasing INPUT_RECORD and UInt16.
    INPUT_RECORD record;
    memcpy(&record, (const unsigned char *)buf + i * sizeof(record), sizeof(record));
    switch (record.EventType) {
      case KEY_EVENT: {
        const KEY_EVENT_RECORD *key = &record.Event.KeyEvent;
        WCHAR unit = key->uChar.UnicodeChar;
        // Alt+Numpad and non-BMP characters arrive on the key-up of `VK_MENU`
        if (unit && (key->bKeyDown || key->wVirtualKeyCode == VK_MENU))
          buf[pos++] = unit;
        break;
      }
      case WINDOW_BUFFER_SIZE_EVENT:
        *resized = 1;
        break;
      default:
        break;
    }
  }
  return pos;
}

static
int32_t read_console_input_job_worker(
  struct read_console_input_job *job,
  int32_t *err_out
) {
  struct worker *worker = moonbitlang_async_get_current_worker();
  uint16_t *buf = job->buf;

  DWORD max_records = Moonbit_array_length(buf) * sizeof(*buf) / sizeof(INPUT_RECORD);
  // A record produces at most one code unit; also respect the output limit.
  if (max_records > (DWORD)job->len)
    max_records = job->len;

  while (1) {
    if (moonbitlang_async_enter_cancellable_region(worker)) {
      *err_out = ERROR_OPERATION_ABORTED;
      return -1;
    }

    HANDLE handles[2] = { job->input, job->cancel };
    DWORD ret = WaitForMultipleObjects(2, handles, FALSE, INFINITE);
    moonbitlang_async_leave_cancellable_region(worker);

    if (ret == WAIT_OBJECT_0 + 1) {
      *err_out = ERROR_OPERATION_ABORTED;
      return -1;
    }
    if (ret != WAIT_OBJECT_0) {
      *err_out = GetLastError();
      return -1;
    }

    DWORD n_records = 0;
    if (!ReadConsoleInputW(
      job->input,
      (INPUT_RECORD *)buf,
      max_records,
      &n_records
    )) {
      *err_out = GetLastError();
      return -1;
    }

    int32_t resized = 0;
    int32_t n = tty_records_to_text(buf, n_records, &resized);
    if (n > 0) {
      // the records are consumed, so report the resize along with the input
      job->resized = resized;
      return n;
    }
    if (resized)
      return TTY_READ_RESIZED;
  }
}

static
int32_t cancel_read_console_input_job(struct read_console_input_job *job) {
  if (!SetEvent(job->cancel))
    return -1;
  return 1; // `CANCELLATION_STATUS_NEED_WAIT`
}

MOONBIT_FFI_EXPORT
struct read_console_input_job *moonbitlang_async_make_read_console_input_job(
  HANDLE input,
  uint16_t *buf,
  int32_t len,
  int32_t *error
) {
  struct read_console_input_job *job = MAKE_JOB(
    read_console_input,
    cancel_read_console_input_job
  );
  job->input = input;
  job->cancel = CreateEventW(NULL, FALSE, FALSE, NULL);
  *error = job->cancel ? 0 : GetLastError();
  job->buf = buf;
  job->len = len;
  job->resized = 0;
  return job;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_read_console_input_job_get_resized(
  struct read_console_input_job *job
) {
  return job->resized;
}

#endif
