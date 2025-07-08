#include <unistd.h>

#ifdef __linux__
#include <sys/epoll.h>

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
  EPOLLIN | EPOLLOUT,
  EPOLLERR
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

  events |= EPOLLET;

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

  events |= EPOLLET;

  epoll_data_t data;
  data.fd = fd;
  struct epoll_event event = { events, data };
  return epoll_ctl(epfd, EPOLL_CTL_MOD, fd, &event);
}

int poll_remove(int epfd, int fd, int events) {
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

int event_get_events(struct epoll_event *ev) {
  if (ev->events & EPOLLERR)
    return 4;

  int result = 0;
  if (ev->events & EPOLLIN)
    result |= 1;
  if (ev->events & EPOLLOUT)
    result |= 2;

  return result;
}

// end of epoll backend
#elif defined(__MACH__) || defined(BSD)

#include <time.h>
#include <sys/event.h>

int poll_create() {
  return kqueue();
}

void poll_destroy(int kqfd) {
  close(kqfd);
}

const int ev_masks[] = {
  0,
  EVFILT_READ,
  EVFILT_WRITE,
  EVFILT_READ | EVFILT_WRITE,
  EV_ERROR
};

int poll_register(int kqfd, int fd, int events, int oneshot) {
  int filter = ev_masks[events];

  int flags = EV_ADD | EV_CLEAR;
  if (oneshot)
    flags |= EV_DISPATCH;

  struct kevent event;
  EV_SET(&event, fd, filter, flags, 0, 0, 0);
  return kevent(kqfd, &event, 1, 0, 0, 0);
}

int poll_modify(int kqfd, int fd, int events, int oneshot) {
  return poll_register(kqfd, fd, events, oneshot);
}

int poll_remove(int kqfd, int fd, int events) {
  struct kevent event;
  EV_SET(&event, fd, ev_masks[events], EV_DELETE, 0, 0, 0);
  return kevent(kqfd, &event, 1, 0, 0, 0);
}

#define EVENT_BUFFER_SIZE 1024
struct kevent event_buffer[EVENT_BUFFER_SIZE];

int poll_wait(int kqfd, int timeout) {
  struct timespec timeout_spec = { timeout / 1000, (timeout / 1000) * 1000 };
  return kevent(kqfd, 0, 0, event_buffer, EVENT_BUFFER_SIZE, &timeout_spec);
}

// wrapper for handling event list
struct kevent *event_list_get(int index) {
  return event_buffer + index;
}

int event_get_fd(struct kevent *ev) {
  return ev->ident;
}

int event_get_events(struct kevent *ev) {
  if (ev->flags | EV_ERROR)
    return 4;

  int result = 0;
  if (ev->filter & EVFILT_READ)
    result |= 1;
  if (ev->filter & EVFILT_WRITE)
    result |= 2;

  return result;
}

// end of kqueue backend
#endif
