#include <sys/epoll.h>
#include <unistd.h>

int poll_create() {
  return epoll_create1(0);
}

void poll_destroy(int epfd) {
  close(epfd);
}

const int ev_masks[] = {
  0,
  EPOLLIN,
  EPOLLOUT,
  EPOLLIN | EPOLLOUT
};

int poll_register(
  int epfd,
  int fd,
  int events,
  int oneshot
) {
  events = ev_masks[events];
  if (oneshot)
    events |= EPOLLONESHOT;

  epoll_data_t data;
  data.fd = fd;
  struct epoll_event event = { events, data };
  return epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &event);
}

int poll_modify(
  int epfd,
  int fd,
  int events,
  int oneshot
) {
  events = ev_masks[events];
  if (oneshot)
    events |= EPOLLONESHOT;

  epoll_data_t data;
  data.fd = fd;
  struct epoll_event event = { events, data };
  return epoll_ctl(epfd, EPOLL_CTL_MOD, fd, &event);
}

int poll_remove(int epfd, int fd) {
  return epoll_ctl(epfd, EPOLL_CTL_DEL, fd, 0);
}

#define EVENT_BUFFER_SIZE 1024
struct epoll_event event_buffer[EVENT_BUFFER_SIZE];

int poll_wait(int epfd, int timeout) {
  return epoll_wait(epfd, event_buffer, EVENT_BUFFER_SIZE, timeout);
}

// wrapper for handling event list
struct epoll_event* event_list_get(int index) {
  return event_buffer + index;
}

int event_get_fd(struct epoll_event *ev) {
  return ev->data.fd;
}
