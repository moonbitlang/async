#include <stdint.h>
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

int moonbitlang_async_bind(int sockfd, struct sockaddr_in *addr) {
  return bind(sockfd, (struct sockaddr*)addr, sizeof(struct sockaddr_in));
}

int moonbitlang_async_listen(int sockfd) {
  return listen(sockfd, 0);
}

int moonbitlang_async_accept(int sockfd, struct sockaddr_in *addr_buf) {
  socklen_t socklen = sizeof(struct sockaddr_in);
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

int moonbitlang_async_connect(int sockfd, struct sockaddr_in *addr) {
  return connect(sockfd, (struct sockaddr*)addr, sizeof(struct sockaddr_in));
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
  socklen_t addr_size = sizeof(struct sockaddr_in);
  return recvfrom(sockfd, buf + offset, max_len, 0, addr_buf, &addr_size);
}

int moonbitlang_async_sendto(int sockfd, void *buf, int offset, int max_len, void *addr) {
  return sendto(sockfd, buf + offset, max_len, 0, addr, sizeof(struct sockaddr_in));
}
