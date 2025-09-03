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
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/tcp.h>
#include <netdb.h>
#include <stdio.h>
#include <fcntl.h>
#include <moonbit.h>

int moonbitlang_async_make_tcp_socket() {
  return socket(AF_INET, SOCK_STREAM, 0);
}

int moonbitlang_async_make_udp_socket() {
  return socket(AF_INET, SOCK_DGRAM, 0);
}

int moonbitlang_async_bind(int sockfd, struct sockaddr_in *addr) {
  return bind(sockfd, (struct sockaddr*)addr, sizeof(struct sockaddr_in));
}

int moonbitlang_async_listen(int sockfd) {
  return listen(sockfd, SOMAXCONN);
}

int moonbitlang_async_recv(int sockfd, void *buf, int offset, int max_len) {
  return recv(sockfd, buf + offset, max_len, 0);
}

int moonbitlang_async_send(int sockfd, void *buf, int offset, int max_len) {
  return send(sockfd, buf + offset, max_len, 0);
}

int moonbitlang_async_enable_keepalive(
  int sock,
  int keep_idle,
  int keep_cnt,
  int keep_intvl
) {
  int value = 1;
  if (setsockopt(sock, SOL_SOCKET, SO_KEEPALIVE, &value, sizeof(int)) < 0)
    return -1;

  if (keep_cnt > 0) {
    if (setsockopt(sock, IPPROTO_TCP, TCP_KEEPCNT, &keep_cnt, sizeof(int)) < 0)
      return -1;
  }

  if (keep_idle > 0) {
#ifdef __MACH__
    if (setsockopt(sock, IPPROTO_TCP, TCP_KEEPALIVE, &keep_idle, sizeof(int)) < 0)
      return -1;
#else
    if (setsockopt(sock, IPPROTO_TCP, TCP_KEEPIDLE, &keep_idle, sizeof(int)) < 0)
      return -1;
#endif
  }

  if (keep_intvl > 0) {
    if (setsockopt(sock, IPPROTO_TCP, TCP_KEEPINTVL, &keep_intvl, sizeof(int)) < 0)
      return -1;
  }

  return 0;
}

void *moonbitlang_async_make_ip_addr(uint32_t ip, int port) {
  struct sockaddr_in *addr = (struct sockaddr_in*)moonbit_make_bytes(
    sizeof(struct sockaddr_in),
    0
  );
  addr->sin_family = AF_INET;
  addr->sin_port = htons(port);
  addr->sin_addr.s_addr = htonl(ip);
  return addr;
}

uint32_t moonbitlang_async_ip_addr_get_ip(struct sockaddr_in *addr) {
  return ntohl(addr->sin_addr.s_addr);
}

uint32_t moonbitlang_async_ip_addr_get_port(struct sockaddr_in *addr) {
  return ntohs(addr->sin_port);
}

int32_t moonbitlang_async_addrinfo_is_null(struct addrinfo *addrinfo) {
  return addrinfo == 0;
}

uint32_t moonbitlang_async_addrinfo_get_ip(struct addrinfo *addrinfo) {
  return ntohl(((struct sockaddr_in*)(addrinfo->ai_addr))->sin_addr.s_addr);
}

struct addrinfo *moonbitlang_async_addrinfo_get_next(struct addrinfo *addrinfo) {
  return addrinfo->ai_next;
}
