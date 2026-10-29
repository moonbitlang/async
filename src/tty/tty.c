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
#include <stdio.h>
#include <sys/ioctl.h>
#include <unistd.h>

#ifdef __linux__
#include <asm/ioctls.h>
#include <asm/termbits.h>
#else
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <termios.h>
#endif

#endif

#ifndef _WIN32

// Write the path of the controlling terminal to `path`, return its length.
// On macOS `/dev/tty` cannot be polled, so find the device behind it.
MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_path(char *path, int32_t len) {
#ifdef __linux__
  const char *name = "/dev/tty";
#else
  struct kinfo_proc info;
  size_t info_len = sizeof(info);
  int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
  if (sysctl(mib, 4, &info, &info_len, NULL, 0) < 0)
    return -1;

  if (info.kp_eproc.e_tdev == NODEV) {
    errno = ENXIO;
    return -1;
  }
  char *dev = devname(info.kp_eproc.e_tdev, S_IFCHR);
  if (!dev) {
    errno = ENXIO;
    return -1;
  }
  char name[64];
  snprintf(name, sizeof(name), "/dev/%s", dev);
#endif
  int32_t name_len = strlen(name);
  if (name_len > len) {
    errno = ENAMETOOLONG;
    return -1;
  }
  memcpy(path, name, name_len);
  return name_len;
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
