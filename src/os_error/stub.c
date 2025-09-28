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

#include <errno.h>
#include <string.h>

int moonbitlang_async_get_errno() {
  return errno;
}

int moonbitlang_async_is_nonblocking_io_error(int err) {
  return err == EAGAIN || err == EINPROGRESS || err == EWOULDBLOCK;
}

char *moonbitlang_async_errno_to_string(int err) {
  return strerror(err);
}
