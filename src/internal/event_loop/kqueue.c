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

#if defined(__MACH__) || defined(BSD)

#include <unistd.h>
#include <time.h>
#include <fcntl.h>
#include <sys/event.h>
#include <sys/wait.h>
#include <errno.h>

int moonbitlang_async_event_bus_create() {
  int kq = kqueue();
  if (kq < 0)
    return -1;

  int flags = fcntl(kq, F_GETFD);
  if (flags < 0)
    goto on_error;

  if (!(flags & FD_CLOEXEC) && fcntl(kq, F_SETFD, flags | FD_CLOEXEC))
    goto on_error;

  return kq;

on_error:
  close(kq);
  return -1;
}

void moonbitlang_async_event_bus_destroy(int kqfd) {
  close(kqfd);
}

/* return value:
   `-1` => failure
   `0` => fd not supported
   `1` => successfully registered
 */
int32_t moonbitlang_async_event_bus_register(int kqfd, int fd, int32_t read_only) {
  // File descriptors registered with the event bus
  // should always be used in a non-blocking manner, due to our use of `EV_CLEAR`.
  // Error is intentionally omitted here, because some special file descriptors,
  // such as another `kqueue`, may not have the concept of blocking/nonblocking at all.
  int fd_flags = fcntl(fd, F_GETFL);
  if (fd_flags >= 0 && !(fd_flags & O_NONBLOCK))
    fcntl(fd, F_SETFL, fd_flags | O_NONBLOCK);

  int flags = EV_ADD | EV_CLEAR | EV_RECEIPT;

  struct kevent events[2], receipts[2];
  EV_SET(&events[0], fd, EVFILT_READ, flags, 0, 0, 0);
  if (!read_only)
    EV_SET(&events[1], fd, EVFILT_WRITE, flags, 0, 0, 0);

  int ret = kevent(kqfd, events, read_only ? 1 : 2, receipts, 2, 0);
  if (ret < 0)
    return ret;

  /* If any of the filter (`EVFILT_READ`/`EVFILT_WRITE`) is registered,
     treat the fd as "pollable".
     Note that `kqueue` support registering regular file with `EVFILT_READ`,
     but the semantic is not very useful.
     So we still rely on `st_mode` to do filtering before `event_bus_register` */
  for (int i = 0; i < ret; ++i)
    if (receipts[i].data == 0)
      return 1;

  return 0;
}

// return value:
// - `> 0`: success, return the pid itself
// - `-1`: failure
// - `0`: pid already terminated
int moonbitlang_async_event_bus_register_pid(int kqfd, pid_t pid) {
  struct kevent event;
#ifdef __MACH__
  EV_SET(&event, pid, EVFILT_PROC, EV_ADD, NOTE_EXITSTATUS, 0, 0);
#else
  EV_SET(&event, pid, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, 0);
#endif
  int ret = kevent(kqfd, &event, 1, 0, 0, 0);

  if (ret >= 0) {
    return 1;
  } else if (errno == ESRCH) {
    return 0;
  } else {
    return -1;
  }
}

#define EVENT_BUFFER_SIZE 1024
static struct kevent event_buffer[EVENT_BUFFER_SIZE];

int moonbitlang_async_event_bus_wait(int kqfd, int timeout) {
  struct timespec timeout_spec = { timeout / 1000, (timeout % 1000) * 1000000 };
  return kevent(
    kqfd,
    0,
    0,
    event_buffer,
    EVENT_BUFFER_SIZE,
    timeout < 0 ? 0 : &timeout_spec
  );
}

// wrapper for handling event list
struct kevent *moonbitlang_async_event_list_get(int kqfd, int index) {
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

#endif
