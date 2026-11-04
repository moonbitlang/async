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

#if defined(_WIN32)

#include <windows.h>

// `@tty.State` interprets the bytes of `tty_state_t`:
// the input and output console modes, little-endian.
typedef struct {
  DWORD in;
  DWORD out;
} tty_state_t;

#elif defined(__linux__)

#include <sys/ioctl.h>
#include <asm/ioctls.h>
#include <asm/termbits.h>

typedef int HANDLE;
// the kernel `struct termios2`, which `TCGETS2` and `TCSETS2` use,
// unlike the `struct termios` of glibc
typedef struct termios2 tty_state_t;

#elif defined(__MACH__)

#include <errno.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <termios.h>
#include <unistd.h>

typedef int HANDLE;
typedef struct termios tty_state_t;

#endif

#ifndef _WIN32
// On macOS `/dev/tty` cannot be polled, so find the device behind it.
MOONBIT_FFI_EXPORT
const char *moonbitlang_async_tty_name(void) {
#if defined(__linux__)
  return "tty";
#elif defined(__MACH__)
  struct kinfo_proc info;
  size_t info_len = sizeof(info);
  int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
  if (sysctl(mib, 4, &info, &info_len, NULL, 0) < 0)
    return NULL;

  if (info.kp_eproc.e_tdev == NODEV) {
    errno = ENXIO;
    return NULL;
  }
  char *dev_name = devname(info.kp_eproc.e_tdev, S_IFCHR);
  if (!dev_name)
    errno = ENXIO;
  return dev_name;
#endif
}
#endif

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_get_state(HANDLE input, HANDLE output, tty_state_t *state) {
#if defined(_WIN32)
  if (!GetConsoleMode(input, &state->in) || !GetConsoleMode(output, &state->out))
    return -1;
#elif defined(__linux__)
  (void)output;
  if (ioctl(input, TCGETS2, state) < 0)
    return -1;
#elif defined(__MACH__)
  (void)output;
  if (tcgetattr(input, state) < 0)
    return -1;
#endif

  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_set_state(HANDLE input, HANDLE output, const tty_state_t *state) {
#if defined(_WIN32)
  if (!SetConsoleMode(input, state->in) || !SetConsoleMode(output, state->out))
    return -1;
  return 0;
#elif defined(__linux__)
  (void)output;
  return ioctl(input, TCSETS2, state);
#elif defined(__MACH__)
  (void)output;
  return tcsetattr(input, TCSANOW, state);
#endif
}

MOONBIT_FFI_EXPORT
int64_t moonbitlang_async_tty_size(HANDLE output) {
  int64_t rows, cols;
#ifdef _WIN32
  CONSOLE_SCREEN_BUFFER_INFO info;
  if (!GetConsoleScreenBufferInfo(output, &info))
    return -1;

  // `dwSize` includes scrollback
  rows = info.srWindow.Bottom - info.srWindow.Top + 1;
  cols = info.srWindow.Right - info.srWindow.Left + 1;
#else
  struct winsize ws;
  if (ioctl(output, TIOCGWINSZ, &ws) < 0)
    return -1;

  rows = ws.ws_row;
  cols = ws.ws_col;
#endif

  return (rows << 32) | cols;
}
