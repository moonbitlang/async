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

#include <fcntl.h>
#include <stdint.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>
#include <moonbit.h>

int moonbitlang_async_make_open_flags(
  int mode,
  int sync_mode,
  int append,
  int create,
  int trunc
) {
  static int modes[] = { O_RDONLY, O_WRONLY, O_RDWR };
  static int sync_modes[] = { 0, O_DSYNC, O_SYNC };

  int flags = modes[mode] | sync_modes[sync_mode];
  if (append)
    flags |= O_APPEND;
  if (trunc)
    flags |= O_TRUNC;
  if (create)
    flags |= O_CREAT;

  return flags;
}

int64_t moonbitlang_async_lseek(int fd, int64_t offset, int mode) {
  static int whence_list[] = { SEEK_SET, SEEK_END, SEEK_CUR };
  return lseek(fd, offset, whence_list[mode]);
}

int moonbitlang_async_dir_is_null(DIR *dir) {
  return dir == 0;
}

moonbit_bytes_t moonbitlang_async_dirent_name(struct dirent *dirent) {
  int len = strlen(dirent->d_name);
  moonbit_bytes_t result = moonbit_make_bytes(len, 0);
  memcpy(result, dirent->d_name, len);
  return result;
}

int moonbitlang_async_dirent_is_null(struct dirent *dirent) {
  return dirent == 0;
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

int32_t moonbitlang_async_file_kind(int fd) {
  struct stat stat;

  if (fstat(fd, &stat) < 0)
    return -1;

  return moonbitlang_async_file_kind_from_stat(&stat);
}

int moonbitlang_async_r_ok() {
  return R_OK;
}

int moonbitlang_async_w_ok() {
  return W_OK;
}

int moonbitlang_async_x_ok() {
  return X_OK;
}

int moonbitlang_async_f_ok() {
  return F_OK;
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
