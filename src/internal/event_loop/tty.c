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

#include <stdlib.h>
#include <string.h>

#ifdef _WIN32

#include <windows.h>

#else

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#ifdef __linux__
#include <poll.h>
#include <sys/signalfd.h>
#else
#include <sys/event.h>
#include <sys/select.h>
#include <sys/time.h>
#endif

#endif

// Provided by `src/internal/event_loop/thread_pool.c`.
// The tty read job is defined here but runs on the shared thread pool.
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

// ===========================================================
// ================ Windows console record encoder ===========
// ===========================================================
//
// Converts Windows console `INPUT_RECORD`s into the VT byte stream that a
// Unix terminal would send. It works on the raw 20-byte record layout
// rather than the Windows type, so it is compiled on every platform and
// can be tested with hand-built records anywhere.
//
// | Record                                   | Effect                       |
// |------------------------------------------|------------------------------|
// | `KEY_EVENT`, key down, `UnicodeChar != 0`| UTF-8 of the character       |
// | `KEY_EVENT`, Alt key up, `UnicodeChar != 0` | UTF-8 of the character    |
// | other `KEY_EVENT`s                       | dropped                      |
// | `FOCUS_EVENT`                            | `CSI I` / `CSI O`            |
// | anything else                            | dropped                      |
//
// Characters entered with Alt+Numpad, and characters the console cannot map
// to a key (ConPTY does this for text outside the BMP), arrive on the key-up
// record of `VK_MENU`, after a key-down record without a character.
//
// With `ENABLE_VIRTUAL_TERMINAL_INPUT` conhost already delivers special keys
// as VT characters, so key codes and modifiers are not looked at.
// `wRepeatCount` is ignored as well, so that a record never produces more
// than four bytes.
//
// Resize is not part of the byte stream. The caller passes the current
// window size with every batch, and the encoder reports whether it changed
// since the last batch.

#define TTY_RECORD_SIZE 20
#define TTY_VK_MENU 0x12

enum {
  TTY_KEY_EVENT = 0x1,
  TTY_FOCUS_EVENT = 0x10,
};

struct tty_encoder {
  // Unpaired high surrogate from the last key-down record, or zero.
  uint16_t pending_high;
  // The window size at the last batch.
  int32_t last_rows;
  int32_t last_cols;
  // Bytes produced but not delivered because the caller's buffer was full,
  // starting at `pending[pending_off]`.
  int32_t pending_off;
  int32_t pending_len;
  uint8_t pending[8];
};

static
uint16_t tty_read_u16(const uint8_t *p) {
  return (uint16_t)(p[0] | (p[1] << 8));
}

static
uint32_t tty_read_u32(const uint8_t *p) {
  return (uint32_t)p[0]
    | ((uint32_t)p[1] << 8)
    | ((uint32_t)p[2] << 16)
    | ((uint32_t)p[3] << 24);
}

// Write `bytes` to `buf`, keeping whatever does not fit in `enc->pending`.
static
void tty_emit(
  struct tty_encoder *enc,
  uint8_t *buf,
  int32_t len,
  int32_t *pos,
  const uint8_t *bytes,
  int32_t n
) {
  for (int32_t i = 0; i < n; ++i) {
    if (*pos < len) {
      buf[(*pos)++] = bytes[i];
    } else if (enc->pending_off + enc->pending_len < (int32_t)sizeof(enc->pending)) {
      enc->pending[enc->pending_off + enc->pending_len++] = bytes[i];
    }
  }
}

static
void tty_emit_code_point(
  struct tty_encoder *enc,
  uint8_t *buf,
  int32_t len,
  int32_t *pos,
  uint32_t c
) {
  uint8_t bytes[4];
  int32_t n;
  if (c < 0x80) {
    bytes[0] = (uint8_t)c;
    n = 1;
  } else if (c < 0x800) {
    bytes[0] = (uint8_t)(0xC0 | (c >> 6));
    bytes[1] = (uint8_t)(0x80 | (c & 0x3F));
    n = 2;
  } else if (c < 0x10000) {
    bytes[0] = (uint8_t)(0xE0 | (c >> 12));
    bytes[1] = (uint8_t)(0x80 | ((c >> 6) & 0x3F));
    bytes[2] = (uint8_t)(0x80 | (c & 0x3F));
    n = 3;
  } else {
    bytes[0] = (uint8_t)(0xF0 | (c >> 18));
    bytes[1] = (uint8_t)(0x80 | ((c >> 12) & 0x3F));
    bytes[2] = (uint8_t)(0x80 | ((c >> 6) & 0x3F));
    bytes[3] = (uint8_t)(0x80 | (c & 0x3F));
    n = 4;
  }
  tty_emit(enc, buf, len, pos, bytes, n);
}

// Encode one UTF-16 code unit, joining surrogate pairs across calls.
// An unpaired high surrogate is dropped, an unpaired low one becomes U+FFFD.
// Dropping rather than replacing the high half keeps every unit at no more
// than four bytes of output.
static
void tty_emit_utf16(
  struct tty_encoder *enc,
  uint8_t *buf,
  int32_t len,
  int32_t *pos,
  uint16_t unit
) {
  if (unit >= 0xD800 && unit < 0xDC00) {
    enc->pending_high = unit;
    return;
  }

  uint32_t c = unit;
  if (unit >= 0xDC00 && unit < 0xE000) {
    if (enc->pending_high) {
      c = 0x10000 + (((uint32_t)enc->pending_high - 0xD800) << 10) + (unit - 0xDC00);
    } else {
      c = 0xFFFD;
    }
  }
  enc->pending_high = 0;
  tty_emit_code_point(enc, buf, len, pos, c);
}

// Move bytes left over by the previous call into `buf`.
static
int32_t tty_flush_pending(struct tty_encoder *enc, uint8_t *buf, int32_t len) {
  int32_t n = enc->pending_len < len ? enc->pending_len : len;
  memcpy(buf, enc->pending + enc->pending_off, n);
  enc->pending_off += n;
  enc->pending_len -= n;
  if (enc->pending_len == 0)
    enc->pending_off = 0;
  return n;
}

// Encode `count` records into `buf[0:len]`, after any bytes left over by the
// previous call. Return the number of bytes written. Bytes that do not fit
// are kept for the next call; at most four bytes per record are produced.
//
// `rows`/`cols` is the current window size, ignored if not positive.
// `*resized` is set if it differs from the size seen by the last batch.
static
int32_t tty_encode_records(
  struct tty_encoder *enc,
  const uint8_t *records,
  int32_t count,
  int32_t rows,
  int32_t cols,
  uint8_t *buf,
  int32_t len,
  int32_t *resized
) {
  int32_t pos = tty_flush_pending(enc, buf, len);
  for (int32_t i = 0; i < count; ++i) {
    const uint8_t *record = records + i * TTY_RECORD_SIZE;
    switch (tty_read_u16(record)) {
      case TTY_KEY_EVENT: {
        uint32_t key_down = tty_read_u32(record + 4);
        uint16_t virtual_key = tty_read_u16(record + 10);
        uint16_t unit = tty_read_u16(record + 14);
        if (unit && (key_down || virtual_key == TTY_VK_MENU))
          tty_emit_utf16(enc, buf, len, &pos, unit);
        break;
      }
      case TTY_FOCUS_EVENT: {
        uint8_t seq[3] = { 0x1b, '[', tty_read_u32(record + 4) ? 'I' : 'O' };
        tty_emit(enc, buf, len, &pos, seq, 3);
        break;
      }
      default:
        break;
    }
  }

  if (rows > 0 && cols > 0 && (rows != enc->last_rows || cols != enc->last_cols)) {
    enc->last_rows = rows;
    enc->last_cols = cols;
    *resized = 1;
  }
  return pos;
}

// Exported for tests, which drive the encoder with hand-built records.

MOONBIT_FFI_EXPORT
struct tty_encoder *moonbitlang_async_tty_encoder_new(int32_t rows, int32_t cols) {
  struct tty_encoder *enc = (struct tty_encoder*)malloc(sizeof(struct tty_encoder));
  memset(enc, 0, sizeof(struct tty_encoder));
  enc->last_rows = rows;
  enc->last_cols = cols;
  return enc;
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_tty_encoder_free(struct tty_encoder *enc) {
  free(enc);
}

// `records` holds `length / 20` records. `result[0]` receives the resize flag.
MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_encoder_encode(
  struct tty_encoder *enc,
  moonbit_bytes_t records,
  int32_t rows,
  int32_t cols,
  uint8_t *buf,
  int32_t *result
) {
  int32_t resized = 0;
  int32_t n = tty_encode_records(
    enc,
    records,
    (int32_t)Moonbit_array_length(records) / TTY_RECORD_SIZE,
    rows,
    cols,
    buf,
    (int32_t)Moonbit_array_length(buf),
    &resized
  );
  result[0] = resized;
  return n;
}

#ifndef _WIN32

// ===========================================================
// ========================== Unix ===========================
// ===========================================================

// The tty handle is allocated with `malloc` and never freed:
// there is one tty per program and it lives as long as the process.
// Fields are only ever touched by one thread at a time:
//
// - `state`/`is_in_raw` are read and written by the main thread only.
// - `resized` is set by the read job (worker thread) and taken by the main
//   thread, but only after the job has completed, so no atomics are needed.
struct tty {
  // `open("/dev/tty", O_RDWR)`, blocking.
  int32_t in_fd;
  // Becomes readable when `SIGWINCH` is pending for the process:
  // a `signalfd` on Linux, a `kqueue` with `EVFILT_SIGNAL` elsewhere.
  //
  // `SIGWINCH` is blocked in every thread, so the signal is never
  // delivered and consumed by its (ignore) default action,
  // and the fd reports it until the read job drains it.
  // This is level-triggered and coalesces a burst into one event.
  // A plain signal handler cannot replace it: on macOS a signal generated
  // while every thread blocks it is parked on one thread and is never
  // handed to another thread that unblocks it later.
  int32_t sig_fd;
  // The original terminal state, valid iff `is_in_raw`.
  struct termios state;
  int32_t is_in_raw;
  // A resize was observed by the read job and not yet reported.
  int32_t resized;
};

static
int32_t open_sigwinch_fd() {
#ifdef __linux__
  sigset_t set;
  sigemptyset(&set);
  sigaddset(&set, SIGWINCH);
  return signalfd(-1, &set, SFD_CLOEXEC | SFD_NONBLOCK);
#else
  int kq = kqueue();
  if (kq < 0)
    return -1;

  fcntl(kq, F_SETFD, FD_CLOEXEC);
  struct kevent ev;
  EV_SET(&ev, SIGWINCH, EVFILT_SIGNAL, EV_ADD, 0, 0, NULL);
  if (kevent(kq, &ev, 1, NULL, 0, NULL) < 0) {
    int err = errno;
    close(kq);
    errno = err;
    return -1;
  }
  return kq;
#endif
}

// Consume the pending `SIGWINCH` report(s), return whether there was any.
static
int32_t drain_sigwinch_fd(int32_t sig_fd) {
  int32_t seen = 0;
#ifdef __linux__
  struct signalfd_siginfo info;
  while (read(sig_fd, &info, sizeof(info)) == sizeof(info))
    seen = 1;
#else
  struct kevent ev;
  struct timespec zero = { 0, 0 };
  while (kevent(sig_fd, NULL, 0, &ev, 1, &zero) > 0)
    seen = 1;
#endif
  return seen;
}

// Open the terminal at `path` (normally `/dev/tty`).
// `out_fd[0]` receives a second descriptor for the same terminal,
// to be owned by the MoonBit output `IoHandle`.
// Returns `NULL` with `errno` set on failure.
MOONBIT_FFI_EXPORT
struct tty *moonbitlang_async_tty_open(moonbit_bytes_t path, int32_t *out_fd) {
  out_fd[0] = -1;
  int in_fd = open((const char*)path, O_RDWR | O_NOCTTY | O_CLOEXEC);
  moonbit_decref(path);
  if (in_fd < 0)
    return NULL;

  int fd = fcntl(in_fd, F_DUPFD_CLOEXEC, 0);
  if (fd < 0)
    goto fail_with_in_fd;

  int sig_fd = open_sigwinch_fd();
  if (sig_fd < 0)
    goto fail_with_fd;

  struct tty *tty = (struct tty*)malloc(sizeof(struct tty));
  if (!tty) {
    errno = ENOMEM;
    goto fail_with_sig_fd;
  }

  // Block `SIGWINCH` in the calling (main) thread from now on.
  // Worker threads and the `sigwait` thread already block every signal,
  // so the signal stays pending and is reported through `sig_fd`.
  sigset_t winch;
  sigemptyset(&winch);
  sigaddset(&winch, SIGWINCH);
  pthread_sigmask(SIG_BLOCK, &winch, NULL);

  memset(tty, 0, sizeof(struct tty));
  tty->in_fd = in_fd;
  tty->sig_fd = sig_fd;
  out_fd[0] = fd;
  return tty;

fail_with_sig_fd:
  close(sig_fd);
fail_with_fd:
  close(fd);
fail_with_in_fd:
  {
    int err = errno;
    close(in_fd);
    errno = err;
  }
  return NULL;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_enter_raw(struct tty *tty) {
  if (tty->is_in_raw)
    return 0;

  struct termios state;
  if (tcgetattr(tty->in_fd, &state) < 0)
    return -1;

  struct termios raw = state;
  cfmakeraw(&raw);
  raw.c_cc[VMIN] = 1;
  raw.c_cc[VTIME] = 0;
  if (tcsetattr(tty->in_fd, TCSANOW, &raw) < 0)
    return -1;

  // store the snapshot only after the mode change succeeded
  tty->state = state;
  tty->is_in_raw = 1;
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_leave_raw(struct tty *tty) {
  if (!tty->is_in_raw)
    return 0;

  if (tcsetattr(tty->in_fd, TCSANOW, &tty->state) < 0)
    return -1;

  tty->is_in_raw = 0;
  return 0;
}

// Returns `(rows << 32) | cols`, or `-1` with `errno` set.
MOONBIT_FFI_EXPORT
int64_t moonbitlang_async_tty_size(struct tty *tty) {
  struct winsize ws;
  if (ioctl(tty->in_fd, TIOCGWINSZ, &ws) < 0)
    return -1;

  return ((int64_t)ws.ws_row << 32) | (int64_t)ws.ws_col;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_take_resize_event(struct tty *tty) {
  int32_t resized = tty->resized;
  tty->resized = 0;
  return resized;
}

// ===== tty read job: wait for input or resize, then read =====

struct tty_read_job {
  struct tty *tty;
  char *buf;
  int32_t offset;
  int32_t len;
};

static
void free_tty_read_job(struct tty_read_job *job) {
  moonbit_decref(job->buf);
}

enum {
  TTY_WAIT_INPUT = 1,
  TTY_WAIT_RESIZE = 2,
};

// Wait until the terminal is readable or `SIGWINCH` is pending.
// Returns a bitset of `TTY_WAIT_*`, or `-1` with `errno` set.
// Input is reported only when it is ready; cancellation shows up as `EINTR`.
static
int32_t tty_wait(struct tty *tty) {
#ifdef __linux__
  struct pollfd pfds[2] = {
    { tty->in_fd, POLLIN, 0 },
    { tty->sig_fd, POLLIN, 0 },
  };
  if (poll(pfds, 2, -1) < 0)
    return -1;

  int32_t ready = 0;
  if (pfds[0].revents)
    ready |= TTY_WAIT_INPUT;
  if (pfds[1].revents)
    ready |= TTY_WAIT_RESIZE;
  return ready;
#else
  // `poll` returns `POLLNVAL` for `/dev/tty` on macOS (poll(2) BUGS: "The
  // poll() system call currently does not support devices"), so use
  // `select`. See `docs/tty-probes/dev_tty_pollable.c`.
  if (tty->in_fd >= FD_SETSIZE || tty->sig_fd >= FD_SETSIZE) {
    errno = EINVAL;
    return -1;
  }

  fd_set readfds;
  FD_ZERO(&readfds);
  FD_SET(tty->in_fd, &readfds);
  FD_SET(tty->sig_fd, &readfds);
  int nfds = (tty->in_fd > tty->sig_fd ? tty->in_fd : tty->sig_fd) + 1;
  if (select(nfds, &readfds, NULL, NULL, NULL) < 0)
    return -1;

  int32_t ready = 0;
  if (FD_ISSET(tty->in_fd, &readfds))
    ready |= TTY_WAIT_INPUT;
  if (FD_ISSET(tty->sig_fd, &readfds))
    ready |= TTY_WAIT_RESIZE;
  return ready;
#endif
}

// Returns the number of bytes read, or `0` with `tty->resized` set
// when the wait ended because of a resize. `0` without the flag is EOF.
// When both input and a resize are ready, input wins and the resize
// is picked up by the next call without blocking.
static
int32_t tty_read_job_worker(struct tty_read_job *job, int32_t *err_out) {
  struct worker *worker = moonbitlang_async_get_current_worker();
  struct tty *tty = job->tty;

  if (moonbitlang_async_enter_cancellable_region(worker)) {
    *err_out = EINTR;
    return -1;
  }

  int32_t ready = tty_wait(tty);
  moonbitlang_async_leave_cancellable_region(worker);

  if (ready < 0) {
    *err_out = errno;
    return -1;
  }

  if (!(ready & TTY_WAIT_INPUT)) {
    if (drain_sigwinch_fd(tty->sig_fd))
      tty->resized = 1;
    return 0;
  }

  if (moonbitlang_async_enter_cancellable_region(worker)) {
    *err_out = EINTR;
    return -1;
  }

  ssize_t n = read(tty->in_fd, job->buf + job->offset, job->len);
  moonbitlang_async_leave_cancellable_region(worker);

  if (n < 0) {
    *err_out = errno;
    return -1;
  }
  return (int32_t)n;
}

MOONBIT_FFI_EXPORT
struct tty_read_job *moonbitlang_async_make_tty_read_job(
  struct tty *tty,
  char *buf,
  int32_t offset,
  int32_t len
) {
  struct tty_read_job *job = MAKE_JOB(tty_read, 0);
  job->tty = tty;
  job->buf = buf;
  job->offset = offset;
  job->len = len;
  return job;
}

#else

// ===========================================================
// ========================= Windows =========================
// ===========================================================

// The tty handle is allocated with `malloc` and never freed, as on Unix.
// Fields are only ever touched by one thread at a time:
//
// - `in_state`/`out_state`/`is_in_raw` are read and written by the main thread only.
// - `enc` is used by the read job only, after being initialized by `open`.
// - `resized` is set by the read job and taken by the main thread,
//   but only after the job has completed, so no atomics are needed.
struct tty {
  // `CONIN$`, non-overlapped: console input cannot be associated with IOCP.
  HANDLE in;
  // `CONOUT$`, for the window size and the output mode only.
  // Output itself goes through a separate handle owned by MoonBit.
  HANDLE out;
  // Auto-reset event set by the cancel handler of the read job,
  // which waits on it together with `in`.
  HANDLE cancel_event;
  // The original console modes, valid iff `is_in_raw`.
  DWORD in_state;
  DWORD out_state;
  int32_t is_in_raw;
  // A resize was observed by the read job and not yet reported.
  int32_t resized;
  struct tty_encoder enc;
};

typedef char tty_record_size_check[sizeof(INPUT_RECORD) == TTY_RECORD_SIZE ? 1 : -1];

static
HANDLE open_console(const WCHAR *name) {
  return CreateFileW(
    name,
    GENERIC_READ | GENERIC_WRITE,
    FILE_SHARE_READ | FILE_SHARE_WRITE,
    NULL,
    OPEN_EXISTING,
    0,
    NULL
  );
}

// The size of the visible window. The screen buffer can be larger
// (legacy conhost includes scrollback in it), so `dwSize` is not used.
static
int32_t get_window_size(HANDLE out, int32_t *rows, int32_t *cols) {
  CONSOLE_SCREEN_BUFFER_INFO info;
  if (!GetConsoleScreenBufferInfo(out, &info))
    return -1;

  *rows = info.srWindow.Bottom - info.srWindow.Top + 1;
  *cols = info.srWindow.Right - info.srWindow.Left + 1;
  return 0;
}

// Open the console of the process. `path` is ignored: the console is always
// `CONIN$` and `CONOUT$`. `out_fd[0]` receives a second `CONOUT$` handle,
// to be owned by the MoonBit output `IoHandle`.
// Returns `NULL` with the last error set on failure.
MOONBIT_FFI_EXPORT
struct tty *moonbitlang_async_tty_open(moonbit_bytes_t path, HANDLE *out_fd) {
  moonbit_decref(path);
  out_fd[0] = INVALID_HANDLE_VALUE;

  HANDLE in = open_console(L"CONIN$");
  if (in == INVALID_HANDLE_VALUE)
    return NULL;

  HANDLE out = open_console(L"CONOUT$");
  if (out == INVALID_HANDLE_VALUE)
    goto fail_with_in;

  HANDLE fd = open_console(L"CONOUT$");
  if (fd == INVALID_HANDLE_VALUE)
    goto fail_with_out;

  HANDLE cancel_event = CreateEventW(NULL, FALSE, FALSE, NULL);
  if (!cancel_event)
    goto fail_with_fd;

  struct tty *tty = (struct tty*)malloc(sizeof(struct tty));
  if (!tty) {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    goto fail_with_cancel_event;
  }

  memset(tty, 0, sizeof(struct tty));
  tty->in = in;
  tty->out = out;
  tty->cancel_event = cancel_event;
  // so that the first batch does not report a resize that did not happen
  get_window_size(out, &tty->enc.last_rows, &tty->enc.last_cols);
  out_fd[0] = fd;
  return tty;

fail_with_cancel_event:
  {
    DWORD err = GetLastError();
    CloseHandle(cancel_event);
    SetLastError(err);
  }
fail_with_fd:
  {
    DWORD err = GetLastError();
    CloseHandle(fd);
    SetLastError(err);
  }
fail_with_out:
  {
    DWORD err = GetLastError();
    CloseHandle(out);
    SetLastError(err);
  }
fail_with_in:
  {
    DWORD err = GetLastError();
    CloseHandle(in);
    SetLastError(err);
  }
  return NULL;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_enter_raw(struct tty *tty) {
  if (tty->is_in_raw)
    return 0;

  DWORD in_state, out_state;
  if (!GetConsoleMode(tty->in, &in_state) || !GetConsoleMode(tty->out, &out_state))
    return -1;

  // - without VT input, special keys never become VT bytes
  // - without window input, there are no resize records to wake the read job
  // - with quick edit on, a mouse click freezes output
  DWORD in_raw =
    (in_state & ~(ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT | ENABLE_PROCESSED_INPUT | ENABLE_QUICK_EDIT_MODE))
    | ENABLE_VIRTUAL_TERMINAL_INPUT
    | ENABLE_WINDOW_INPUT
    | ENABLE_EXTENDED_FLAGS;
  DWORD out_raw =
    out_state
    | ENABLE_PROCESSED_OUTPUT
    | ENABLE_VIRTUAL_TERMINAL_PROCESSING
    | DISABLE_NEWLINE_AUTO_RETURN;

  // A console that predates VT support rejects the flags,
  // fail rather than half-applying raw mode.
  if (!SetConsoleMode(tty->in, in_raw))
    return -1;

  if (!SetConsoleMode(tty->out, out_raw)) {
    DWORD err = GetLastError();
    SetConsoleMode(tty->in, in_state);
    SetLastError(err);
    return -1;
  }

  // store the snapshot only after the mode change succeeded
  tty->in_state = in_state;
  tty->out_state = out_state;
  tty->is_in_raw = 1;
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_leave_raw(struct tty *tty) {
  if (!tty->is_in_raw)
    return 0;

  if (!SetConsoleMode(tty->in, tty->in_state))
    return -1;

  if (!SetConsoleMode(tty->out, tty->out_state))
    return -1;

  tty->is_in_raw = 0;
  return 0;
}

// Returns `(rows << 32) | cols`, or `-1` with the last error set.
MOONBIT_FFI_EXPORT
int64_t moonbitlang_async_tty_size(struct tty *tty) {
  int32_t rows, cols;
  if (get_window_size(tty->out, &rows, &cols) < 0)
    return -1;

  return ((int64_t)rows << 32) | (int64_t)cols;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_take_resize_event(struct tty *tty) {
  int32_t resized = tty->resized;
  tty->resized = 0;
  return resized;
}

// ===== tty read job: wait for input or resize, then read =====

#define TTY_MAX_RECORDS 256

struct tty_read_job {
  struct tty *tty;
  char *buf;
  int32_t offset;
  int32_t len;
  // Whether to read records (raw mode) or cooked text.
  // Decided when the job is created, on the main thread, which owns `is_in_raw`.
  int32_t raw;
  union {
    INPUT_RECORD records[TTY_MAX_RECORDS];
    WCHAR chars[TTY_MAX_RECORDS * TTY_RECORD_SIZE / sizeof(WCHAR)];
  } scratch;
};

static
void free_tty_read_job(struct tty_read_job *job) {
  moonbit_decref(job->buf);
}

// Raw mode: wait on `CONIN$` and the cancel event, then drain records and
// encode them as VT bytes. Returns the number of bytes, or `0` with
// `tty->resized` set when the batch only changed the window size.
// Batches that produce neither (key-up records, ...) are skipped.
//
// The cancellable region wraps only the wait. Records consumed by
// `ReadConsoleInputW` are gone from the console, so they are always
// encoded and delivered even if cancellation arrived meanwhile.
static
int32_t tty_read_raw(struct tty_read_job *job, int32_t *err_out) {
  struct worker *worker = moonbitlang_async_get_current_worker();
  struct tty *tty = job->tty;
  uint8_t *buf = (uint8_t*)job->buf + job->offset;

  if (tty->enc.pending_len > 0)
    return tty_flush_pending(&tty->enc, buf, job->len);

  // every record expands to at most four bytes
  DWORD max_records = job->len / 4;
  if (max_records < 1)
    max_records = 1;
  if (max_records > TTY_MAX_RECORDS)
    max_records = TTY_MAX_RECORDS;

  // A cancellation request may have arrived after a previous job stopped waiting.
  // Any request for this job comes after `Cancelling` is set,
  // which `enter_cancellable_region` checks after this reset.
  ResetEvent(tty->cancel_event);

  while (1) {
    if (moonbitlang_async_enter_cancellable_region(worker)) {
      *err_out = ERROR_OPERATION_ABORTED;
      return -1;
    }

    HANDLE handles[2] = { tty->in, tty->cancel_event };
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
    if (!GetNumberOfConsoleInputEvents(tty->in, &available)) {
      *err_out = GetLastError();
      return -1;
    }
    if (available == 0)
      continue;

    DWORD n_records = 0;
    if (!ReadConsoleInputW(
      tty->in,
      job->scratch.records,
      available < max_records ? available : max_records,
      &n_records
    )) {
      *err_out = GetLastError();
      return -1;
    }

    // Compare the window size on every batch rather than only on
    // `WINDOW_BUFFER_SIZE_EVENT`: legacy conhost only reports buffer size
    // changes, so a resize it misses is still reported with the next input.
    int32_t rows = 0, cols = 0;
    if (get_window_size(tty->out, &rows, &cols) < 0)
      rows = cols = 0;

    int32_t resized = 0;
    int32_t n = tty_encode_records(
      &tty->enc,
      (const uint8_t*)job->scratch.records,
      (int32_t)n_records,
      rows,
      cols,
      buf,
      job->len,
      &resized
    );
    if (resized)
      tty->resized = 1;
    if (n > 0 || resized)
      return n;
  }
}

// Cooked mode: read a line with `ReadConsoleW`, as `@stdio.stdin` does,
// and convert it to UTF-8. Returns `0` at end of input.
// Cancelled by the default `CancelSynchronousIo` handler.
static
int32_t tty_read_cooked(struct tty_read_job *job, int32_t *err_out) {
  struct worker *worker = moonbitlang_async_get_current_worker();
  struct tty *tty = job->tty;
  uint8_t *buf = (uint8_t*)job->buf + job->offset;

  if (tty->enc.pending_len > 0)
    return tty_flush_pending(&tty->enc, buf, job->len);

  // every code unit expands to at most three bytes
  DWORD max_chars = job->len / 3;
  if (max_chars < 1)
    max_chars = 1;
  if (max_chars > sizeof(job->scratch.chars) / sizeof(WCHAR))
    max_chars = sizeof(job->scratch.chars) / sizeof(WCHAR);

  while (1) {
    if (moonbitlang_async_enter_cancellable_region(worker)) {
      *err_out = ERROR_OPERATION_ABORTED;
      return -1;
    }

    DWORD n_chars = 0;
    BOOL ok = ReadConsoleW(tty->in, job->scratch.chars, max_chars, &n_chars, NULL);
    moonbitlang_async_leave_cancellable_region(worker);

    if (!ok) {
      DWORD err = GetLastError();
      if (err == ERROR_HANDLE_EOF || err == ERROR_BROKEN_PIPE)
        return 0;
      *err_out = err;
      return -1;
    }
    if (n_chars == 0)
      return 0;

    int32_t pos = 0;
    for (DWORD i = 0; i < n_chars; ++i)
      tty_emit_utf16(&tty->enc, buf, job->len, &pos, job->scratch.chars[i]);

    // zero bytes means the read ended with the high half of a surrogate pair
    if (pos > 0)
      return pos;
  }
}

static
int32_t tty_read_job_worker(struct tty_read_job *job, int32_t *err_out) {
  return job->raw ? tty_read_raw(job, err_out) : tty_read_cooked(job, err_out);
}

static
int32_t cancel_tty_read_job(struct tty_read_job *job) {
  SetEvent(job->tty->cancel_event);
  return 1; // `CANCELLATION_STATUS_NEED_WAIT`
}

MOONBIT_FFI_EXPORT
struct tty_read_job *moonbitlang_async_make_tty_read_job(
  struct tty *tty,
  char *buf,
  int32_t offset,
  int32_t len
) {
  struct tty_read_job *job = tty->is_in_raw
    ? MAKE_JOB(tty_read, cancel_tty_read_job)
    : MAKE_JOB(tty_read, 0);
  job->tty = tty;
  job->buf = buf;
  job->offset = offset;
  job->len = len;
  job->raw = tty->is_in_raw;
  return job;
}

#endif
