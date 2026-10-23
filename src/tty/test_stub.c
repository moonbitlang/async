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

// Pseudo terminal helpers, used by tests only.

// glibc only declares `posix_openpt`/`grantpt`/`unlockpt`/`ptsname` with it.
// Without a declaration `ptsname` is assumed to return `int`,
// which truncates the pointer on 64-bit.
#ifdef __linux__
#define _GNU_SOURCE
#endif

#include <stdint.h>
#include <moonbit.h>

#ifndef _WIN32

#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

// Create a pseudo terminal, return the master side or `-1`.
MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_test_open_pty() {
  int master = posix_openpt(O_RDWR | O_NOCTTY);
  if (master < 0)
    return -1;

  if (grantpt(master) < 0 || unlockpt(master) < 0) {
    close(master);
    return -1;
  }

  fcntl(master, F_SETFD, FD_CLOEXEC);
  return master;
}

// The path of the slave side of a pseudo terminal.
MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbitlang_async_tty_test_pty_name(int32_t master) {
  const char *name = ptsname(master);
  if (!name)
    name = "";

  int32_t len = (int32_t)strlen(name);
  moonbit_bytes_t result = moonbit_make_bytes(len, 0);
  memcpy(result, name, len);
  return result;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_test_set_size(int32_t fd, int32_t rows, int32_t cols) {
  struct winsize ws;
  memset(&ws, 0, sizeof(ws));
  ws.ws_row = (unsigned short)rows;
  ws.ws_col = (unsigned short)cols;
  return ioctl(fd, TIOCSWINSZ, &ws);
}

// Send `SIGWINCH` to the whole process, as the kernel does on a real resize.
MOONBIT_FFI_EXPORT
void moonbitlang_async_tty_test_send_winch() {
  kill(getpid(), SIGWINCH);
}

#endif
