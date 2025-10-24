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

int moonbitlang_async_fd_is_nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0)
    return flags;

  return (flags & O_NONBLOCK) > 0;
}

int moonbitlang_async_set_blocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0) return flags;

  if (flags & O_NONBLOCK) {
    if (fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) < 0)
      return -1;
  }

  return 0;
}

int moonbitlang_async_set_nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0) return flags;

  if (!(flags & O_NONBLOCK)) {
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0)
      return -1;
  }

  return 0;
}

int moonbitlang_async_set_cloexec(int fd) {
  int flags = fcntl(fd, F_GETFD);
  if (flags < 0) return flags;

  if (!(flags & FD_CLOEXEC)) {
    if (fcntl(fd, F_SETFD, flags | FD_CLOEXEC) < 0)
      return -1;
  }

  return 0;
}

int moonbitlang_async_pipe(int *fds) {
  if (pipe(fds) < 0)
    return -1;

  for (int i = 0; i < 2; ++i) {
    if (moonbitlang_async_set_cloexec(fds[i]) < 0)
      return -1;
  }

  return 0;
}
