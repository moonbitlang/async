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

#ifdef _WIN32

#include <windows.h>

#else

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
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
//
// Not implemented yet. Every entry point fails with
// `ERROR_CALL_NOT_IMPLEMENTED` so that the package still compiles.

struct tty {
  int32_t unused;
};

MOONBIT_FFI_EXPORT
struct tty *moonbitlang_async_tty_open(moonbit_bytes_t path, HANDLE *out_fd) {
  moonbit_decref(path);
  out_fd[0] = INVALID_HANDLE_VALUE;
  SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
  return NULL;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_enter_raw(struct tty *tty) {
  (void)tty;
  SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
  return -1;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_leave_raw(struct tty *tty) {
  (void)tty;
  SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
  return -1;
}

MOONBIT_FFI_EXPORT
int64_t moonbitlang_async_tty_size(struct tty *tty) {
  (void)tty;
  SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
  return -1;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_take_resize_event(struct tty *tty) {
  (void)tty;
  return 0;
}

struct tty_read_job {
  struct tty *tty;
  char *buf;
};

static
void free_tty_read_job(struct tty_read_job *job) {
  moonbit_decref(job->buf);
}

static
int32_t tty_read_job_worker(struct tty_read_job *job, int32_t *err_out) {
  (void)job;
  *err_out = ERROR_CALL_NOT_IMPLEMENTED;
  return -1;
}

MOONBIT_FFI_EXPORT
struct tty_read_job *moonbitlang_async_make_tty_read_job(
  struct tty *tty,
  char *buf,
  int32_t offset,
  int32_t len
) {
  (void)offset;
  (void)len;
  struct tty_read_job *job = MAKE_JOB(tty_read, 0);
  job->tty = tty;
  job->buf = buf;
  return job;
}

#endif
