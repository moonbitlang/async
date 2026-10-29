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

enum {
  TTY_MAX_RECORDS = 256,
};

struct tty_read_console_input_job {
  HANDLE input;
  HANDLE wakeup;
  uint16_t *buf;
  int32_t offset;
  int32_t len;
  // set when input is returned and a resize was read with it
  int32_t resized;
};

static
void free_tty_read_console_input_job(struct tty_read_console_input_job *job) {
  moonbit_decref(job->buf);
}

static
int32_t tty_records_to_text(
  const INPUT_RECORD *records,
  DWORD count,
  uint16_t *buf,
  int32_t *resized
) {
  int32_t pos = 0;
  for (DWORD i = 0; i < count; ++i) {
    switch (records[i].EventType) {
      case KEY_EVENT: {
        const KEY_EVENT_RECORD *key = &records[i].Event.KeyEvent;
        WCHAR unit = key->uChar.UnicodeChar;
        // Alt+Numpad and non-BMP characters arrive on the key-up of `VK_MENU`
        if (unit && (key->bKeyDown || key->wVirtualKeyCode == VK_MENU))
          buf[pos++] = unit;
        break;
      }
      case FOCUS_EVENT:
        buf[pos++] = 0x1b;
        buf[pos++] = '[';
        buf[pos++] = records[i].Event.FocusEvent.bSetFocus ? 'I' : 'O';
        break;
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
int32_t tty_read_console_input_job_worker(
  struct tty_read_console_input_job *job,
  int32_t *err_out
) {
  struct worker *worker = moonbitlang_async_get_current_worker();
  uint16_t *buf = job->buf + job->offset;

  INPUT_RECORD records[TTY_MAX_RECORDS];

  // a record produces at most three code units
  DWORD max_records = job->len / 3;
  if (max_records > TTY_MAX_RECORDS)
    max_records = TTY_MAX_RECORDS;

  // clear a cancellation left by a previous job
  ResetEvent(job->wakeup);

  while (1) {
    if (moonbitlang_async_enter_cancellable_region(worker)) {
      *err_out = ERROR_OPERATION_ABORTED;
      return -1;
    }

    HANDLE handles[2] = { job->input, job->wakeup };
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

    DWORD available = 0;
    if (!GetNumberOfConsoleInputEvents(job->input, &available)) {
      *err_out = GetLastError();
      return -1;
    }
    if (available == 0)
      continue;

    DWORD n_records = 0;
    if (!ReadConsoleInputW(
      job->input,
      records,
      available < max_records ? available : max_records,
      &n_records
    )) {
      *err_out = GetLastError();
      return -1;
    }

    int32_t resized = 0;
    int32_t n = tty_records_to_text(records, n_records, buf, &resized);
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
int32_t cancel_tty_read_console_input_job(struct tty_read_console_input_job *job) {
  SetEvent(job->wakeup);
  return 1; // `CANCELLATION_STATUS_NEED_WAIT`
}

MOONBIT_FFI_EXPORT
struct tty_read_console_input_job *moonbitlang_async_make_tty_read_console_input_job(
  HANDLE input,
  HANDLE wakeup,
  uint16_t *buf,
  int32_t offset,
  int32_t len
) {
  struct tty_read_console_input_job *job = MAKE_JOB(
    tty_read_console_input,
    cancel_tty_read_console_input_job
  );
  job->input = input;
  job->wakeup = wakeup;
  job->buf = buf;
  job->offset = offset;
  job->len = len;
  job->resized = 0;
  return job;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_read_console_input_job_get_resized(
  struct tty_read_console_input_job *job
) {
  return job->resized;
}

#endif
