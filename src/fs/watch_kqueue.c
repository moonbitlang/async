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

#ifdef __MACH__
#include <time.h>
#include <sys/event.h>
#endif

#include "moonbit.h"
_Noreturn void moonbit_panic();

#ifndef __MACH__
struct kevent;
#endif

MOONBIT_FFI_EXPORT
int moonbitlang_async_kqueue_watcher_create() {
#ifdef __MACH__
  return kqueue();
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_kqueue_watcher_buffer_size() {
#ifdef __MACH__
  return 1024 * sizeof(struct kevent);
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int moonbitlang_async_kqueue_watcher_add_file(int kq, int fd) {
#ifdef __MACH__
  struct kevent event;
  EV_SET(
    &event,
    fd,
    EVFILT_VNODE,
    EV_ADD | EV_CLEAR,
    NOTE_WRITE | NOTE_EXTEND,
    0,
    0
  );

  return kevent(kq, &event, 1, 0, 0, 0);
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int moonbitlang_async_kqueue_watcher_remove_file(int kq, int fd) {
#ifdef __MACH__
  struct kevent event;
  EV_SET(&event, fd,EVFILT_VNODE, EV_DELETE, 0, 0, 0);
  return kevent(kq, &event, 1, 0, 0, 0);
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_kqueue_watcher_event_size() {
#ifdef __MACH__
  return sizeof(struct kevent);
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
struct kevent *moonbitlang_async_kqueue_watcher_get_event(struct kevent *buf, int32_t index) {
#ifdef __MACH__
  return buf + index;
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_kqueue_watcher_fetch_event(int kq, void *buf) {
#ifdef __MACH__
  int buffer_size = Moonbit_array_length(buf) / sizeof(struct kevent);
  struct timespec timeout = { 0, 0 };
  return kevent(kq, 0, 0, buf, buffer_size, &timeout);
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int moonbitlang_async_kqueue_watcher_event_get_fd(struct kevent *event) {
#ifdef __MACH__
  return event->ident;
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_kqueue_watcher_event_has_modify(struct kevent *event) {
#ifdef __MACH__
  return (event->filter & (NOTE_WRITE | NOTE_EXTEND)) != 0;
#else
  moonbit_panic();
#endif
}

#endif
