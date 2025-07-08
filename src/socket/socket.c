#include <stdint.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <fcntl.h>
#include <moonbit.h>

int make_tcp_socket() {
  int sock = socket(AF_INET, SOCK_STREAM, 0);
  if (sock > 0)
    fcntl(sock, F_SETFL, O_NONBLOCK);
  return sock;
}

int make_udp_socket() {
  int sock = socket(AF_INET, SOCK_DGRAM, 0);
  if (sock > 0)
    fcntl(sock, F_SETFL, O_NONBLOCK);
  return sock;
}

int bind_ffi(int sockfd, struct sockaddr_in *addr) {
  return bind(sockfd, (struct sockaddr*)addr, sizeof(struct sockaddr_in));
}

int listen_ffi(int sockfd) {
  return listen(sockfd, 0);
}

int accept_ffi(int sockfd, struct sockaddr_in *addr_buf) {
  socklen_t socklen = sizeof(struct sockaddr_in);
  int conn = accept(sockfd, (struct sockaddr*)addr_buf, &socklen);
  if (conn > 0) {
    fcntl(conn, F_SETFL, O_NONBLOCK);
  }
  return conn;
}

int connect_ffi(int sockfd, struct sockaddr_in *addr) {
  return connect(sockfd, (struct sockaddr*)addr, sizeof(struct sockaddr_in));
}

int recv_ffi(int sockfd, void *buf, int offset, int max_len) {
  return recv(sockfd, buf + offset, max_len, 0);
}

int send_ffi(int sockfd, void *buf, int offset, int max_len) {
  return send(sockfd, buf + offset, max_len, 0);
}

int getsockerr(int sockfd) {
  int err, opt_len = sizeof(int);
  if (getsockopt(sockfd, SOL_SOCKET, SO_ERROR, &err, &opt_len) < 0)
    return -1;
  return err;
}

void *make_ip_addr(uint32_t ip, int port) {
  struct sockaddr_in *addr = (struct sockaddr_in*)moonbit_make_bytes(
    sizeof(struct sockaddr_in),
    0
  );
  addr->sin_family = AF_INET;
  addr->sin_port = htons(port);
  addr->sin_addr.s_addr = htonl(ip);
  return addr;
}

uint32_t ip_addr_get_ip(struct sockaddr_in *addr) {
  return ntohl(addr->sin_addr.s_addr);
}

uint32_t ip_addr_get_port(struct sockaddr_in *addr) {
  return ntohs(addr->sin_port);
}

int recvfrom_ffi(int sockfd, void *buf, int offset, int max_len, void *addr_buf) {
  socklen_t addr_size = sizeof(struct sockaddr_in);
  return recvfrom(sockfd, buf + offset, max_len, 0, addr_buf, &addr_size);
}

int sendto_ffi(int sockfd, void *buf, int offset, int max_len, void *addr) {
  return sendto(sockfd, buf + offset, max_len, 0, addr, sizeof(struct sockaddr_in));
}
