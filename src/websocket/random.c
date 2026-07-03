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
#include <bcrypt.h>

#pragma comment (lib, "Bcrypt.lib")

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_websocket_random_bytes(void *buf, int32_t len) {
  if (len < 0) {
    return -1;
  }
  return BCryptGenRandom(NULL, buf, len, BCRYPT_USE_SYSTEM_PREFERRED_RNG) ==
    STATUS_SUCCESS ? 0 : -1;
}

#else

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_websocket_random_bytes(void *buf, int32_t len) {
  if (len < 0) {
    return -1;
  }

  int fd = open("/dev/urandom", O_RDONLY);
  if (fd < 0) {
    return -1;
  }

  unsigned char *out = buf;
  int32_t written = 0;
  while (written < len) {
    ssize_t n = read(fd, out + written, (size_t)(len - written));
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      close(fd);
      return -1;
    }
    if (n == 0) {
      close(fd);
      return -1;
    }
    written += (int32_t)n;
  }

  return close(fd);
}

#endif
