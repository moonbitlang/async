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

int moonbitlang_async_get_R_OK() {
  return R_OK;
}

int moonbitlang_async_get_W_OK() {
  return W_OK;
}

int moonbitlang_async_get_X_OK() {
  return X_OK;
}

int moonbitlang_async_get_F_OK() {
  return F_OK;
}

int moonbitlang_async_get_O_RDONLY() {
  return O_RDONLY;
}

int moonbitlang_async_get_O_WRONLY() {
  return O_WRONLY;
}

int moonbitlang_async_get_O_RDWR() {
  return O_RDWR;
}

int moonbitlang_async_get_O_SYNC() {
  return O_SYNC;
}

int moonbitlang_async_get_O_DSYNC() {
  return O_DSYNC;
}

int moonbitlang_async_get_O_APPEND() {
  return O_APPEND;
}

int moonbitlang_async_get_O_TRUNC() {
  return O_TRUNC;
}

int moonbitlang_async_get_O_CREAT() {
  return O_CREAT;
}
