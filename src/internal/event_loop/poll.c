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

#include <unistd.h>

#ifdef __linux__
#include <sys/syscall.h>
#include <sys/epoll.h>
#include <sys/wait.h>
#include <errno.h>

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

// use mask to classify different kinds of entity
static const uint64_t pid_mask = (uint64_t)1 << 63;

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
  data.u64 = fd;
  struct epoll_event event = { events, data };
  int op = prev_events == 0 ? EPOLL_CTL_ADD : EPOLL_CTL_MOD;
  return epoll_ctl(epfd, op, fd, &event);
}

int moonbitlang_async_poll_register_pid(int epfd, pid_t pid) {
  int pidfd = syscall(SYS_pidfd_open, pid, 0);
  if (pidfd < 0)
    return -1;

  epoll_data_t data;
  data.u64 = pid_mask | pidfd;

  struct epoll_event event = { EPOLLIN, data };
  int ret = epoll_ctl(epfd, EPOLL_CTL_ADD, pidfd, &event);
  if (ret < 0)
    return ret;

  return pidfd;
}

int moonbitlang_async_poll_remove(int epfd, int fd, int events) {
  return epoll_ctl(epfd, EPOLL_CTL_DEL, fd, 0);
}

int moonbitlang_async_poll_remove_pid(int epfd, int pidfd) {
  int ret = epoll_ctl(epfd, EPOLL_CTL_DEL, pidfd, 0);
  close(pidfd);
  return ret;
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
  return ev->data.u64 & ~pid_mask;
}

int moonbitlang_async_event_get_events(struct epoll_event *ev) {
  if (ev->data.u64 & pid_mask)
    return 4;

  if (ev->events & (EPOLLERR | EPOLLHUP | EPOLLRDHUP))
    return 3;

  int result = 0;
  if (ev->events & EPOLLIN)
    result |= 1;
  if (ev->events & EPOLLOUT)
    result |= 2;

  return result;
}

int moonbitlang_async_event_get_pid_status(struct epoll_event *ev, int *out) {
  int pid_fd = ev->data.u64 & ~pid_mask;
  siginfo_t info;
  int ret = waitid(P_PIDFD, pid_fd, &info, WEXITED | WSTOPPED | WNOHANG);
  if (ret < 0)
    return ret;

  *out = info.si_status;
  return 0;
}

// end of epoll backend
#elif defined(__MACH__) || defined(BSD)

#include <time.h>
#include <sys/event.h>
#include <sys/wait.h>

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
  EVFILT_READ | EVFILT_WRITE
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

int moonbitlang_async_poll_register_pid(int kqfd, pid_t pid) {
  struct kevent event;
#ifdef __MACH__
  EV_SET(&event, pid, EVFILT_PROC, EV_ADD, NOTE_EXITSTATUS, 0, 0);
#else
  EV_SET(&event, pid, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, 0);
#endif
  int ret = kevent(kqfd, &event, 1, 0, 0, 0);
  if (ret < 0)
    return ret;

  return pid;
}

int moonbitlang_async_poll_remove(int kqfd, int fd, int events) {
  struct kevent event;
  EV_SET(&event, fd, ev_masks[events], EV_DELETE, 0, 0, 0);
  return kevent(kqfd, &event, 1, 0, 0, 0);
}

int moonbitlang_async_poll_remove_pid(int kqfd, pid_t pid) {
  // after the process exit, the pid is automatically removed
  return 0;
}

#define EVENT_BUFFER_SIZE 1024
static struct kevent event_buffer[EVENT_BUFFER_SIZE];

int moonbitlang_async_poll_wait(int kqfd, int timeout) {
  struct timespec timeout_spec = { timeout / 1000, (timeout / 1000) * 1000000 };
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

  if (ev->filter == EVFILT_PROC)
    return 4;

  if (ev->flags & EV_ERROR)
    return 3;

  return 0;
}

int moonbitlang_async_event_get_pid_status(struct kevent *ev, int *out) {
  int wstatus = ev->data;
  *out = WEXITSTATUS(wstatus);
  return 0;
}

// end of kqueue backend
#endif
