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

#include <sys/socket.h>
#include <moonbit.h>

int moonbitlang_async_connect(int sockfd, moonbit_bytes_t addr) {
  return connect(sockfd, (struct sockaddr*)addr, Moonbit_array_length(addr));
}

int moonbitlang_async_accept(int sockfd, moonbit_bytes_t addr_buf) {
  socklen_t socklen = Moonbit_array_length(addr_buf);
  return accept(sockfd, (struct sockaddr*)addr_buf, &socklen);
}

int moonbitlang_async_getsockerr(int sockfd) {
  int err = 0;
  socklen_t opt_len = sizeof(int);
  if (getsockopt(sockfd, SOL_SOCKET, SO_ERROR, &err, &opt_len) < 0)
    return -1;
  return err;
}
