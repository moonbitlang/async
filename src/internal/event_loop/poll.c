#include <unistd.h>

#ifdef __linux__
#include <sys/epoll.h>

int moonbitlang_async_poll_create() {
  return epoll_create1(0);
}

void moonbitlang_async_poll_destroy(int epfd) {
  close(epfd);
}

static const int ev_masks[] = {
  0,
  EPOLLIN,
  EPOLLOUT,
  EPOLLIN | EPOLLOUT,
};

int moonbitlang_async_poll_register(
  int epfd,
  int fd,
  int prev_events,
  int new_events,
  int oneshot
) {
  int events = ev_masks[prev_events | new_events];
  if (oneshot)
    events |= EPOLLONESHOT;

  events |= EPOLLET;

  epoll_data_t data;
  data.fd = fd;
  struct epoll_event event = { events, data };
  int op = prev_events == 0 ? EPOLL_CTL_ADD : EPOLL_CTL_MOD;
  return epoll_ctl(epfd, op, fd, &event);
}

int moonbitlang_async_poll_remove(int epfd, int fd, int events) {
  return epoll_ctl(epfd, EPOLL_CTL_DEL, fd, 0);
}

#define EVENT_BUFFER_SIZE 1024
static struct epoll_event event_buffer[EVENT_BUFFER_SIZE];

int moonbitlang_async_poll_wait(int epfd, int timeout) {
  return epoll_wait(epfd, event_buffer, EVENT_BUFFER_SIZE, timeout);
}

// wrapper for handling event list
struct epoll_event* moonbitlang_async_event_list_get(int index) {
  return event_buffer + index;
}

int moonbitlang_async_event_get_fd(struct epoll_event *ev) {
  return ev->data.fd;
}

int moonbitlang_async_event_get_events(struct epoll_event *ev) {
  if (ev->events & (EPOLLERR | EPOLLHUP | EPOLLRDHUP))
    return 3;

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

int moonbitlang_async_poll_create() {
  return kqueue();
}

void moonbitlang_async_poll_destroy(int kqfd) {
  close(kqfd);
}

static const int ev_masks[] = {
  0,
  EVFILT_READ,
  EVFILT_WRITE,
  EVFILT_READ | EVFILT_WRITE,
};

int moonbitlang_async_poll_register(
  int kqfd,
  int fd,
  int prev_events,
  int new_events,
  int oneshot
) {
  int filter = ev_masks[new_events];

  int flags = EV_ADD | EV_CLEAR;
  if (oneshot)
    flags |= EV_DISPATCH;

  struct kevent event;
  EV_SET(&event, fd, filter, flags, 0, 0, 0);
  return kevent(kqfd, &event, 1, 0, 0, 0);
}

int moonbitlang_async_poll_remove(int kqfd, int fd, int events) {
  struct kevent event;
  EV_SET(&event, fd, ev_masks[events], EV_DELETE, 0, 0, 0);
  return kevent(kqfd, &event, 1, 0, 0, 0);
}

#define EVENT_BUFFER_SIZE 1024
static struct kevent event_buffer[EVENT_BUFFER_SIZE];

int moonbitlang_async_poll_wait(int kqfd, int timeout) {
  struct timespec timeout_spec = { timeout / 1000, (timeout / 1000) * 1000 };
  return kevent(kqfd, 0, 0, event_buffer, EVENT_BUFFER_SIZE, &timeout_spec);
}

// wrapper for handling event list
struct kevent *moonbitlang_async_event_list_get(int index) {
  return event_buffer + index;
}

int moonbitlang_async_event_get_fd(struct kevent *ev) {
  return ev->ident;
}

int moonbitlang_async_event_get_events(struct kevent *ev) {
  if (ev->filter == EVFILT_READ)
    return 1;

  if (ev->filter == EVFILT_WRITE)
    return 2;

  if (ev->flags & EV_ERROR)
    return 3;

  return 0;
}

// end of kqueue backend
#endif
