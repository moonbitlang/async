#include <stdint.h>
#include <sys/socket.h>
#include <arpa/inet.h>

int make_tcp_socket() {
  return socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);
}

int bind_ffi(int sockfd, uint32_t ip, int sport) {
  struct sockaddr_in addr = { AF_INET, htons(sport), htonl(ip) };
  return bind(sockfd, (struct sockaddr*)&addr, sizeof(struct sockaddr_in));
}

int listen_ffi(int sockfd) {
  return listen(sockfd, 0);
}

int accept_ffi(int sockfd) {
  return accept(sockfd, 0, 0);
}

int recv_ffi(int sockfd, void *buf, int buf_size) {
  return recv(sockfd, buf, buf_size, 0);
}

int send_ffi(int sockfd, void *buf, int buf_size) {
  return send(sockfd, buf, buf_size, 0);
}
