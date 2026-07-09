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
#include <stdio.h>
#include "moonbit.h"

#if _WIN32_WINNT >= 0x0A00
#define HAS_ReadDirectoryChangesExW
#endif

#ifdef HAS_ReadDirectoryChangesExW
typedef FILE_NOTIFY_EXTENDED_INFORMATION fs_event_t;
#else
typedef FILE_NOTIFY_INFORMATION fs_event_t;
#endif

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_has_ReadDirectoryChangesExW() {
#ifdef HAS_ReadDirectoryChangesExW
  return 1;
#else
  return 0;
#endif
}


MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_watcher_event_buffer_size() {
  return sizeof(fs_event_t) * 16384;
}

MOONBIT_FFI_EXPORT
fs_event_t *moonbitlang_async_watcher_get_event(char *buf, int32_t offset) {
  return (fs_event_t*)(buf + offset);
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_watcher_event_get_size(char *buf, int32_t offset) {
  fs_event_t *event = (fs_event_t*)(buf + offset);
  printf("%.*S: %d\n", event->FileNameLength / 2, event->FileName, event->Action);
  return event->NextEntryOffset;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_watcher_event_is_modify_event(char *buf, int32_t offset) {
  fs_event_t *event = (fs_event_t*)(buf + offset);
  return event->Action == FILE_ACTION_MODIFIED;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_watcher_event_get_path_len(char *buf, int32_t offset) {
  fs_event_t *event = (fs_event_t*)(buf + offset);
  return event->FileNameLength;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_watcher_event_get_path_offset() {
  return offsetof(fs_event_t, FileName);
}

MOONBIT_FFI_EXPORT
uint64_t moonbitlang_async_watcher_event_get_file_id(fs_event_t *event) {
#ifdef HAS_ReadDirectoryChangesExW
  return event->FileId.QuadPart;
#else
  moonbit_panic();
#endif
}

MOONBIT_FFI_EXPORT
uint64_t moonbitlang_async_watcher_event_get_parent_file_id(fs_event_t *event) {
#ifdef HAS_ReadDirectoryChangesExW
  return event->ParentFileId.QuadPart;
#else
  moonbit_panic();
#endif
}

#endif
