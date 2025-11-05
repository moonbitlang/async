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
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

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

int32_t moonbitlang_async_sizeof_stat() {
  return sizeof(struct stat);
}

int32_t moonbitlang_async_file_kind_from_stat(struct stat *stat) {
  switch (stat->st_mode & S_IFMT) {
  case S_IFREG:  return 1;
  case S_IFDIR:  return 2;
  case S_IFLNK:  return 3;
  case S_IFSOCK: return 4;
  case S_IFIFO:  return 5;
  case S_IFBLK:  return 6;
  case S_IFCHR:  return 7;
  default:       return 0;
  }
}

int64_t moonbitlang_async_file_size_from_stat(struct stat *stat) {
  return stat->st_size;
}

#ifdef __MACH__
#define GET_STAT_TIMESTAMP(statp, kind) (statp)->st_##kind##timespec
#else
#define GET_STAT_TIMESTAMP(statp, kind) (statp)->st_##kind##tim
#endif

void moonbitlang_async_atime_from_stat(
  struct stat *stat,
  int64_t *sec_out,
  int32_t *nsec_out
) {
  *sec_out = GET_STAT_TIMESTAMP(stat, a).tv_sec;
  *nsec_out = GET_STAT_TIMESTAMP(stat, a).tv_nsec;
}

void moonbitlang_async_mtime_from_stat(
  struct stat *stat,
  int64_t *sec_out,
  int32_t *nsec_out
) {
  *sec_out = GET_STAT_TIMESTAMP(stat, m).tv_sec;
  *nsec_out = GET_STAT_TIMESTAMP(stat, m).tv_nsec;
}

void moonbitlang_async_ctime_from_stat(
  struct stat *stat,
  int64_t *sec_out,
  int32_t *nsec_out
) {
  *sec_out = GET_STAT_TIMESTAMP(stat, c).tv_sec;
  *nsec_out = GET_STAT_TIMESTAMP(stat, c).tv_nsec;
}
