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

#include <string.h>

#ifdef _WIN32

#include <windows.h>

#else

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <unistd.h>

#ifdef __linux__
#include <asm/ioctls.h>
#include <asm/termbits.h>
#include <sys/signalfd.h>
#else
#include <termios.h>
#include <sys/event.h>
#include <sys/time.h>
#endif

#endif

#ifndef _WIN32

// Readable while `SIGWINCH` is pending. A signal handler does not work here:
// on macOS, a signal blocked by every thread is never delivered to a thread
// that unblocks it later.
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

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_open(int32_t *fds) {
  int in_fd = open("/dev/tty", O_RDWR | O_NOCTTY | O_CLOEXEC);
  if (in_fd < 0)
    return -1;

  int fd = fcntl(in_fd, F_DUPFD_CLOEXEC, 0);
  if (fd < 0)
    goto fail_with_in_fd;

  int sig_fd = open_sigwinch_fd();
  if (sig_fd < 0)
    goto fail_with_fd;

  // other threads already block every signal, so `SIGWINCH` stays pending
  sigset_t winch;
  sigemptyset(&winch);
  sigaddset(&winch, SIGWINCH);
  pthread_sigmask(SIG_BLOCK, &winch, NULL);

  fds[0] = in_fd;
  fds[1] = sig_fd;
  fds[2] = in_fd;
  fds[3] = fd;
  return 0;

fail_with_fd:
  close(fd);
fail_with_in_fd:
  {
    int err = errno;
    close(in_fd);
    errno = err;
  }
  return -1;
}

#ifdef __linux__
// `@tty.State` interprets the bytes of the kernel `struct termios2`, which
// `TCGETS2` and `TCSETS2` use, unlike the `struct termios` of glibc.
MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_get_state(int32_t input, int32_t output, uint8_t *state) {
  (void)output;
  struct termios2 current;
  if (ioctl(input, TCGETS2, &current) < 0)
    return -1;

  memcpy(state, &current, sizeof(current));
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_set_state(int32_t input, int32_t output, uint8_t *state) {
  (void)output;
  struct termios2 new_state;
  memcpy(&new_state, state, sizeof(new_state));
  return ioctl(input, TCSETS2, &new_state);
}
#else
// `@tty.State` interprets the bytes of `struct termios`.
MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_get_state(int32_t input, int32_t output, uint8_t *state) {
  (void)output;
  struct termios current;
  if (tcgetattr(input, &current) < 0)
    return -1;

  memcpy(state, &current, sizeof(current));
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_set_state(int32_t input, int32_t output, uint8_t *state) {
  (void)output;
  struct termios new_state;
  memcpy(&new_state, state, sizeof(new_state));
  return tcsetattr(input, TCSANOW, &new_state);
}
#endif

MOONBIT_FFI_EXPORT
int64_t moonbitlang_async_tty_size(int32_t output) {
  struct winsize ws;
  if (ioctl(output, TIOCGWINSZ, &ws) < 0)
    return -1;

  return ((int64_t)ws.ws_row << 32) | (int64_t)ws.ws_col;
}
#else

// The input and output console modes, little-endian.
// `@tty.State` interprets these bytes.
struct tty_state {
  DWORD in;
  DWORD out;
};

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

// `dwSize` includes scrollback on legacy conhost
static
int32_t get_window_size(HANDLE out, int32_t *rows, int32_t *cols) {
  CONSOLE_SCREEN_BUFFER_INFO info;
  if (!GetConsoleScreenBufferInfo(out, &info))
    return -1;

  *rows = info.srWindow.Bottom - info.srWindow.Top + 1;
  *cols = info.srWindow.Right - info.srWindow.Left + 1;
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_open(HANDLE *fds) {
  HANDLE in = open_console(L"CONIN$");
  if (in == INVALID_HANDLE_VALUE)
    return -1;

  HANDLE out = open_console(L"CONOUT$");
  if (out == INVALID_HANDLE_VALUE)
    goto fail_with_in;

  HANDLE fd;
  if (!DuplicateHandle(
    GetCurrentProcess(), out, GetCurrentProcess(), &fd,
    0, FALSE, DUPLICATE_SAME_ACCESS
  ))
    goto fail_with_out;

  HANDLE cancel_event = CreateEventW(NULL, FALSE, FALSE, NULL);
  if (!cancel_event)
    goto fail_with_fd;

  fds[0] = in;
  fds[1] = cancel_event;
  fds[2] = out;
  fds[3] = fd;
  return 0;

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
  return -1;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_get_state(HANDLE input, HANDLE output, uint8_t *state) {
  struct tty_state current;
  if (!GetConsoleMode(input, &current.in) || !GetConsoleMode(output, &current.out))
    return -1;

  memcpy(state, &current, sizeof(current));
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_set_state(HANDLE input, HANDLE output, uint8_t *state) {
  struct tty_state new_state, old_state;
  memcpy(&new_state, state, sizeof(new_state));
  if (!GetConsoleMode(input, &old_state.in))
    return -1;

  if (!SetConsoleMode(input, new_state.in))
    return -1;

  if (!SetConsoleMode(output, new_state.out)) {
    // e.g. the legacy console rejects the VT output flags
    DWORD err = GetLastError();
    SetConsoleMode(input, old_state.in);
    SetLastError(err);
    return -1;
  }
  return 0;
}

MOONBIT_FFI_EXPORT
int64_t moonbitlang_async_tty_size(HANDLE output) {
  int32_t rows, cols;
  if (get_window_size(output, &rows, &cols) < 0)
    return -1;

  return ((int64_t)rows << 32) | (int64_t)cols;
}
#endif
