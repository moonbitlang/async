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

typedef FILE_ID_BOTH_DIR_INFO sys_dirent;

#elif defined(__MACH__)

#include <sys/types.h>
#include <sys/dirent.h>

// https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/getdirentries.2.html
typedef struct {
   u_int32_t d_fileno; /* file number of entry */
   u_int16_t d_reclen; /* length of this record */
   u_int8_t  d_type;   /* file type, see below */
   u_int8_t  d_namlen; /* length of string in d_name */
   char      d_name[];
} sys_dirent;

#elif defined(__linux__)

#include <unistd.h>
#include <stdint.h>
#include <dirent.h>

// glibc wrapper for this does not exist until 2.30,
// so manually define for compatibility sake.
// Definition come from https://man7.org/linux/man-pages/man2/getdents.2.html
typedef struct {
  uint64_t       d_ino;    /* 64-bit inode number */
  int64_t        d_off;    /* Not an offset; see getdents() */
  unsigned short d_reclen; /* Size of this dirent */
  unsigned char  d_type;   /* File type */
  char           d_name[]; /* Filename (null-terminated) */
} sys_dirent;

#else

#error "unsupported platform"

#endif

#include "moonbit.h"

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_dir_buffer_min_size() {
#ifdef _WIN32

  return sizeof(sys_dirent) + MAX_PATH;

#else

  return sizeof(sys_dirent) + NAME_MAX;

#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_dir_entry_length(char *buf, int32_t offset, int32_t len) {
  sys_dirent *ent = (sys_dirent *)(buf + offset);

#ifdef _WIN32

  return ent->NextEntryOffset;

#else

  return ent->d_reclen;

#endif
}

MOONBIT_FFI_EXPORT
char *moonbitlang_async_dir_entry_get_name(char *buf, int32_t offset) {
  sys_dirent *ent = (sys_dirent *)(buf + offset);

#ifdef _WIN32

  return (char*)ent->FileName;

#else

  return ent->d_name;

#endif
}

// 1 => is directory
// 0 => not directory
// -1 => unknown
MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_dir_entry_is_dir(char *buf, int32_t offset) {
  sys_dirent *ent = (sys_dirent *)(buf + offset);

#ifdef _WIN32

  return (ent->FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0
      && (ent->FileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;

#else

  switch (ent->d_type) {
    case DT_UNKNOWN: return -1;
    case DT_DIR:     return 1;
    default:         return 0;
  }

#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_dir_entry_is_hidden(char *buf, int32_t offset) {
  sys_dirent *ent = (sys_dirent *)(buf + offset);

#ifdef _WIN32

  return (ent->FileAttributes & FILE_ATTRIBUTE_HIDDEN) != 0;

#else

  return ent->d_name[0] == '.';

#endif
}
