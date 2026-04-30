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

#ifdef _WIN32

#include <windows.h>
#include "moonbit.h"

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_watcher_event_buffer_size() {
  return sizeof(FILE_NOTIFY_INFORMATION) * 16384;
}

MOONBIT_FFI_EXPORT
FILE_NOTIFY_INFORMATION *moonbitlang_async_watcher_get_event(char *buf, int32_t offset) {
  return (FILE_NOTIFY_INFORMATION*)(buf + offset);
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_watcher_event_get_size(FILE_NOTIFY_INFORMATION *event) {
  return event->NextEntryOffset;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_watcher_event_get_action(FILE_NOTIFY_INFORMATION *event) {
  return event->Action;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_watcher_event_get_name_len(FILE_NOTIFY_INFORMATION *event) {
  return event->FileNameLength;
}

MOONBIT_FFI_EXPORT
char *moonbitlang_async_watcher_event_get_name(FILE_NOTIFY_INFORMATION *event) {
  return event->FileName;
}

#endif
