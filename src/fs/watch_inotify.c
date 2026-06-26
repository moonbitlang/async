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

#include <sys/inotify.h>
#include <unistd.h>
#include <limits.h>
#include <errno.h>

#endif

#ifndef _WIN32

#include "moonbit.h"
_Noreturn void moonbit_panic();

#ifndef __linux__
struct inotify_event;
#endif

MOONBIT_FFI_EXPORT
int moonbitlang_async_inotify_create() {
#ifdef __linux__
  return inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_inotify_remove_file(int inotify, int wd) {
#ifdef __linux__
  return inotify_rm_watch(inotify, wd);
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_inotify_event_buffer_size() {
#ifdef __linux__
  static const int min_size = sizeof(struct inotify_event) + NAME_MAX + 1;
  return 4096 < min_size ? min_size : 4096;
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_inotify_fetch_event(int inotify, void *buf, int32_t buf_len) {
#ifdef __linux__
  int ret = read(inotify, buf, buf_len);
  if (ret > 0) {
    return ret;
  } else if (errno == EAGAIN) {
    return 0;
  } else {
    return -1;
  }
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_inotify_event_get_size(char *buf, int32_t offset) {
  struct inotify_event *event = (struct inotify_event*)(buf + offset);
#ifdef __linux__
  return sizeof(struct inotify_event) + event->len;
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_inotify_event_get_wd(char *buf, int32_t offset) {
  struct inotify_event *event = (struct inotify_event*)(buf + offset);
#ifdef __linux__
  return event->wd;
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_inotify_event_has_relevant_event(char *buf, int32_t offset) {
  struct inotify_event *event = (struct inotify_event*)(buf + offset);
#ifdef __linux__
  return (event->mask & (IN_CREATE | IN_DELETE | IN_MODIFY | IN_MOVED_FROM | IN_MOVED_TO)) != 0;
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_inotify_event_has_overflow(char *buf, int32_t offset) {
  struct inotify_event *event = (struct inotify_event*)(buf + offset);
#ifdef __linux__
  return (event->mask & IN_Q_OVERFLOW) != 0;
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_inotify_event_has_ignore(char *buf, int32_t offset) {
  struct inotify_event *event = (struct inotify_event*)(buf + offset);
#ifdef __linux__
  return (event->mask & IN_IGNORED) != 0;
#else
  moonbit_panic();
#endif
}

#endif // #ifndef _WIN32
