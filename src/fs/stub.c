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

int moonbitlang_async_make_open_flags(
  int mode,
  int sync_mode,
  int append,
  int trunc,
  int create
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
