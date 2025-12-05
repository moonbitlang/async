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

#ifndef _WIN32

#include <stdint.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/tcp.h>
#include <netinet/in.h>
#include <netdb.h>
#include <stdio.h>
#include <fcntl.h>
#include <string.h>
#include <moonbit.h>

int moonbitlang_async_make_tcp_socket(int family) {
  return socket(family == 4 ? AF_INET : AF_INET6, SOCK_STREAM, 0);
}

int moonbitlang_async_disable_nagle(int sock) {
  int enable = 1;
  return setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, &enable, sizeof(int));
}

int moonbitlang_async_allow_reuse_addr(int sock) {
  int reuse_addr = 1;
  return setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse_addr, sizeof(int));
}

int moonbitlang_async_make_udp_socket(int family) {
  return socket(family == 4 ? AF_INET : AF_INET6, SOCK_DGRAM, 0);
}

int moonbitlang_async_bind(int sockfd, struct sockaddr *addr) {
  return bind(sockfd, (struct sockaddr*)addr, Moonbit_array_length(addr));
}

int moonbitlang_async_set_ipv6_only(int sockfd, int ipv6_only) {
  return setsockopt(sockfd, IPPROTO_IPV6, IPV6_V6ONLY, &ipv6_only, sizeof(int));
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
  // For IPv4, create traditional sockaddr_in structure
  struct sockaddr_in *addr = (struct sockaddr_in*)moonbit_make_bytes(
    sizeof(struct sockaddr_in),
    0
  );
  addr->sin_family = AF_INET;
  addr->sin_port = htons(port);
  addr->sin_addr.s_addr = htonl(ip);
  return addr;
}

void *moonbitlang_async_make_empty_addr(int family) {
  if (family == 4) {
    struct sockaddr *addr = (struct sockaddr*)moonbit_make_bytes(
      sizeof(struct sockaddr_in),
      0
    );
    addr->sa_family = AF_INET;
    return addr;
  } else {
    struct sockaddr *addr = (struct sockaddr*)moonbit_make_bytes(
      sizeof(struct sockaddr_in6),
      0
    );
    addr->sa_family = AF_INET6;
    return addr;
  };
}

void *moonbitlang_async_make_ipv6_addr(uint8_t *ip, int port) {
  // For IPv6, create sockaddr_in6 structure directly
  struct sockaddr_in6 *addr = (struct sockaddr_in6*)moonbit_make_bytes(
    sizeof(struct sockaddr_in6),
    0
  );
  addr->sin6_family = AF_INET6;
  addr->sin6_port = htons(port);
  memcpy(&addr->sin6_addr, ip, 16);
  return addr;
}

uint32_t moonbitlang_async_ip_addr_get_ip(struct sockaddr_in *addr) {
  return ntohl(addr->sin_addr.s_addr);
}

uint32_t moonbitlang_async_ip_addr_get_port(struct sockaddr_in *addr) {
  return ntohs(addr->sin_port);
}

int32_t moonbitlang_async_addr_is_ipv6(void *addr_bytes) {
  // Check if the address family is AF_INET6
  // use sa_family to be compatible with more platforms(BSD, Linux)
  struct sockaddr *sa = (struct sockaddr *)addr_bytes;
  return sa->sa_family == AF_INET6;
}

uint8_t *moonbitlang_async_addr_get_ipv6_bytes(struct sockaddr_in6 *addr) {
  return addr->sin6_addr.s6_addr;
}

int32_t moonbitlang_async_addr_is_ipv6_wildcard(struct sockaddr_in6 *addr) {
  uint64_t *chunks = (uint64_t*)(addr->sin6_addr.s6_addr);
  return chunks[0] == 0 && chunks[1] == 0;
}

int32_t moonbitlang_async_addrinfo_is_null(struct addrinfo *addrinfo) {
  return addrinfo == 0;
}

struct addrinfo *moonbitlang_async_addrinfo_get_next(struct addrinfo *addrinfo) {
  return addrinfo->ai_next;
}

void* moonbitlang_async_addrinfo_to_addr(struct addrinfo *addrinfo, int port) {
  if (addrinfo == NULL || addrinfo->ai_addr == NULL) {
    return NULL;
  }

  if (addrinfo->ai_family == AF_INET) {
    // IPv4
    struct sockaddr_in *addr = (struct sockaddr_in*)moonbit_make_bytes(
      sizeof(struct sockaddr_in),
      0
    );
    memcpy(addr, addrinfo->ai_addr, sizeof(struct sockaddr_in));
    addr->sin_port = htons(port);
    return addr;
  } else if (addrinfo->ai_family == AF_INET6) {
    // IPv6
    struct sockaddr_in6 *addr = (struct sockaddr_in6*)moonbit_make_bytes(
      sizeof(struct sockaddr_in6),
      0
    );
    memcpy(addr, addrinfo->ai_addr, sizeof(struct sockaddr_in6));
    addr->sin6_port = htons(port);
    return addr;
  } else {
      return NULL;
  }
}

int moonbitlang_async_getsockname(int sock, struct sockaddr *addr_out) {
  socklen_t len = Moonbit_array_length(addr_out);
  return getsockname(sock, addr_out, &len);
}

#endif
