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

#include <unistd.h>
#include <fcntl.h>

int moonbitlang_async_pipe(int *fds) {
  if (pipe(fds) < 0)
    return -1;

  int flags = fcntl(fds[0], F_GETFD);
  if (flags < 0) return flags;

  if (!(flags & FD_CLOEXEC)) {
    if (fcntl(fds[0], F_SETFD, flags | FD_CLOEXEC) < 0)
      return -1;
  }

  flags = fcntl(fds[1], F_GETFD);
  if (flags < 0) return flags;

  if (!(flags & FD_CLOEXEC)) {
    if (fcntl(fds[1], F_SETFD, flags | FD_CLOEXEC) < 0)
      return -1;
  }

  return 0;
}

int moonbitlang_async_get_blocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0)
    return flags;

  return (flags & O_NONBLOCK) > 0;
}

int moonbitlang_async_set_nonblock(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0)
    return flags;

  if (flags & O_NONBLOCK)
    return 0;

  return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

int moonbitlang_async_set_blocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0)
    return flags;

  if (flags & O_NONBLOCK) {
    return fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);
  }

  return 0;
}

int moonbitlang_async_read(int fd, void *buf, int offset, int max_len) {
  return read(fd, buf + offset, max_len);
}

int moonbitlang_async_write(int fd, void *buf, int offset, int max_len) {
  return write(fd, buf + offset, max_len);
}
