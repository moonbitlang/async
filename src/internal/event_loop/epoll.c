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

#ifdef __linux__

#include <unistd.h>
#include <fcntl.h>
#include <sys/syscall.h>
#include <sys/epoll.h>
#include <sys/wait.h>
#include <linux/version.h>

_Noreturn void moonbit_panic();

int moonbitlang_async_event_bus_create() {
  return epoll_create1(EPOLL_CLOEXEC);
}

void moonbitlang_async_event_bus_destroy(int epfd) {
  close(epfd);
}

static const int ev_masks[] = {
  0,
  EPOLLIN,
  EPOLLOUT,
  EPOLLIN | EPOLLOUT,
};

int moonbitlang_async_event_bus_register(int epfd, int fd, int32_t read_only) {
  // File descriptors registered with the event bus
  // should always be used in a non-blocking manner, due to our use of `EPOLLET`.
  // Error is intentionally omitted here, because some special file descriptors,
  // such as `inotify` instance, may not have the concept of blocking/nonblocking at all.
  int fd_flags = fcntl(fd, F_GETFL);
  if (fd_flags >= 0 && !(fd_flags & O_NONBLOCK))
    fcntl(fd, F_SETFL, fd_flags | O_NONBLOCK);

  int events = EPOLLIN | EPOLLET | EPOLLRDHUP;
  if (!read_only)
    events |= EPOLLOUT;

  epoll_data_t data;
  data.u64 = fd;
  struct epoll_event event = { events, data };
  return epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &event);
}

int moonbitlang_async_event_bus_register_pid(int epfd, pid_t pid) {
  moonbit_panic();
}

#define EVENT_BUFFER_SIZE 1024
static struct epoll_event event_buffer[EVENT_BUFFER_SIZE];

int moonbitlang_async_event_bus_wait(int epfd, int timeout) {
  return epoll_wait(epfd, event_buffer, EVENT_BUFFER_SIZE, timeout);
}

// wrapper for handling event list
struct epoll_event* moonbitlang_async_event_list_get(int index) {
  return event_buffer + index;
}

int moonbitlang_async_event_get_fd(struct epoll_event *ev) {
  return ev->data.u64;
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

#endif
