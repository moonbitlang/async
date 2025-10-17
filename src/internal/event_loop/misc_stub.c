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
#include <netinet/in.h>
#include <unistd.h>
#include <sys/stat.h>
#include <moonbit.h>

int moonbitlang_async_connect(int sockfd, moonbit_bytes_t addr) {
  return connect(sockfd, (struct sockaddr*)addr, Moonbit_array_length(addr));
}

int moonbitlang_async_accept(int sockfd, moonbit_bytes_t addr_buf) {
  socklen_t socklen = sizeof(struct sockaddr_storage); // Use storage size for IPv4/IPv6
  return accept(sockfd, (struct sockaddr*)addr_buf, &socklen);
}

int moonbitlang_async_getsockerr(int sockfd) {
  int err = 0;
  socklen_t opt_len = sizeof(int);
  if (getsockopt(sockfd, SOL_SOCKET, SO_ERROR, &err, &opt_len) < 0)
    return -1;
  return err;
}

int moonbitlang_async_read(int fd, char *buf, int offset, int len) {
  return read(fd, buf + offset, len);
}

int moonbitlang_async_write(int fd, char *buf, int offset, int len) {
  return write(fd, buf + offset, len);
}

int moonbitlang_async_recvfrom(
  int sock,
  char *buf,
  int offset,
  int len,
  moonbit_bytes_t addr
) {
  socklen_t addr_size = sizeof(struct sockaddr_storage); // Use storage size for IPv4/IPv6
  return recvfrom(sock, buf + offset, len, 0, (struct sockaddr*)addr, &addr_size);
}

int moonbitlang_async_sendto(
  int sock,
  char *buf,
  int offset,
  int len,
  moonbit_bytes_t addr
) {
  struct sockaddr *sa = (struct sockaddr*)addr;
  socklen_t addr_len;
  
  // Use the address family to determine the actual length
  if (sa->sa_family == AF_INET) {
    addr_len = sizeof(struct sockaddr_in);
  } else if (sa->sa_family == AF_INET6) {
    addr_len = sizeof(struct sockaddr_in6);
  } else {
    addr_len = sizeof(struct sockaddr_storage);
  }
  
  return sendto(sock, buf + offset, len, 0, sa, addr_len);
}

int32_t moonbitlang_async_sizeof_stat() {
  return sizeof(struct stat);
}

struct dirent *moonbitlang_async_null_dirent() {
  return 0;
}
