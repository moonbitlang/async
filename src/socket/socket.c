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
#include <string.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <fcntl.h>
#include <moonbit.h>

int moonbitlang_async_make_tcp_socket() {
  int sock = socket(AF_INET, SOCK_STREAM, 0);
  if (sock > 0) {
    int flags = fcntl(sock, F_GETFL);
    if (flags < 0)
      return flags;

    if (!(flags & O_NONBLOCK)) {
      int status = fcntl(sock, F_SETFL, flags | O_NONBLOCK);
      if (status < 0)
        return status;
    }
  }
  return sock;
}

int moonbitlang_async_make_udp_socket() {
  int sock = socket(AF_INET, SOCK_DGRAM, 0);
  if (sock > 0) {
    int flags = fcntl(sock, F_GETFL);
    if (flags < 0)
      return flags;

    if (!(flags & O_NONBLOCK)) {
      int status = fcntl(sock, F_SETFL, flags | O_NONBLOCK);
      if (status < 0)
        return status;
    }
  }
  return sock;
}

int moonbitlang_async_bind(int sockfd, struct sockaddr_storage *addr) {
  socklen_t socklen = (addr->ss_family == AF_INET6) ? 
    sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in);
  return bind(sockfd, (struct sockaddr*)addr, socklen);
}


int moonbitlang_async_listen(int sockfd) {
  return listen(sockfd, SOMAXCONN);
}

int moonbitlang_async_accept(int sockfd, struct sockaddr_storage *addr_buf) {
  socklen_t socklen = (addr_buf->ss_family == AF_INET6) ? 
    sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in);
  int conn = accept(sockfd, (struct sockaddr*)addr_buf, &socklen);
  if (conn > 0) {
    int flags = fcntl(conn, F_GETFL);
    if (flags < 0)
      return flags;

    if (!(flags & O_NONBLOCK)) {
      int status = fcntl(conn, F_SETFL, flags | O_NONBLOCK);
      if (status < 0)
        return status;
    }
  }
  return conn;
}

int moonbitlang_async_connect(int sockfd, struct sockaddr_storage *addr) {
  return connect(sockfd, (struct sockaddr*)addr, sizeof(struct sockaddr_storage));
}

int moonbitlang_async_recv(int sockfd, void *buf, int offset, int max_len) {
  return recv(sockfd, buf + offset, max_len, 0);
}

int moonbitlang_async_send(int sockfd, void *buf, int offset, int max_len) {
  return send(sockfd, buf + offset, max_len, 0);
}

int moonbitlang_async_getsockerr(int sockfd) {
  int err;
  socklen_t opt_len = sizeof(int);
  if (getsockopt(sockfd, SOL_SOCKET, SO_ERROR, &err, &opt_len) < 0)
    return -1;
  return err;
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

int moonbitlang_async_recvfrom(int sockfd, void *buf, int offset, int max_len, void *addr_buf) {
  socklen_t addr_size = sizeof(struct sockaddr_storage);
  return recvfrom(sockfd, buf + offset, max_len, 0, addr_buf, &addr_size);
}

int moonbitlang_async_sendto(int sockfd, void *buf, int offset, int max_len, struct sockaddr_storage *addr) {
  socklen_t addr_len = (addr->ss_family == AF_INET6) ? 
      sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in);
  return sendto(sockfd, buf + offset, max_len, 0, (void *)addr, addr_len);
}

void *moonbitlang_async_make_ipv6_addr(uint8_t *ip, int port, uint32_t flowinfo, uint32_t scope_id) {
  struct sockaddr_in6 *addr = (struct sockaddr_in6*)moonbit_make_bytes(
    sizeof(struct sockaddr_in6),
    0
  );
  addr->sin6_family = AF_INET6;
  addr->sin6_port = htons(port);
  addr->sin6_flowinfo = flowinfo;
  addr->sin6_scope_id = scope_id;
  memcpy(&addr->sin6_addr, ip, 16);
  return addr;
}

int32_t moonbitlang_async_ipv6_addr_get_ip(struct sockaddr_in6 *addr, uint8_t *dst) {
  char ip_str[INET6_ADDRSTRLEN];
  if (inet_ntop(AF_INET6, &addr->sin6_addr, ip_str, sizeof(ip_str)) == NULL) {
      return -1;
  }
  int len = strlen(ip_str);
  memcpy(dst, ip_str, len);
  dst[len] = '\0';
  return len;
}
uint32_t moonbitlang_async_ipv6_addr_get_port(struct sockaddr_in6 *addr) {
  return ntohs(addr->sin6_port);
}