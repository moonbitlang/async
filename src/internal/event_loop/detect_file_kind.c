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

#include <winsock2.h>
#include <windows.h>

#else

#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

#endif

#include "moonbit.h"

enum FileKind {
  UnknownFileKind = 0,
  Regular = 1,
  Directory = 2,
  SymLink = 3,
  Socket = 4,
  Pipe = 5,
  BlockDevice = 6,
  CharDevice = 7
};

#ifdef _WIN32

static
BOOL handle_is_socket(HANDLE handle) {
  int opt = 0;
  int opt_len = sizeof(int);
  return 0 == getsockopt((SOCKET)handle, SOL_SOCKET, SO_TYPE, (char*)&opt, &opt_len);
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_kind_of_fd(HANDLE handle) {
  SetLastError(0);
  DWORD kind = GetFileType(handle);
  switch (kind) {
    case FILE_TYPE_DISK: {
      FILE_BASIC_INFO info;
      if (
        !GetFileInformationByHandleEx(
          handle,
          FileBasicInfo,
          &info,
          sizeof(FILE_BASIC_INFO)
        )
      ) {
        return -1;
      }
      if (info.FileAttributes & FILE_ATTRIBUTE_DIRECTORY)
        return Directory;
      else if (info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)
        return SymLink;
      else
        return Regular;
    }
    case FILE_TYPE_CHAR:    return CharDevice;
    case FILE_TYPE_PIPE:    return handle_is_socket(handle) > 0 ? Socket : Pipe;
    case FILE_TYPE_UNKNOWN: {
      int get_file_type_err = GetLastError();
      if (handle_is_socket(handle))
        return Socket;
      else if (get_file_type_err == 0)
        return UnknownFileKind;

      SetLastError(get_file_type_err);
      return -1;
    }
    default:                return UnknownFileKind;
  }
}

#else // #ifdef _WIN32

int32_t moonbitlang_async_file_kind_from_stat(struct stat *stat) {
  switch (stat->st_mode & S_IFMT) {
    case S_IFREG:  return Regular;
    case S_IFDIR:  return Directory;
    case S_IFLNK:  return SymLink;
    case S_IFSOCK: return Socket;
    case S_IFIFO:  return Pipe;
    case S_IFBLK:  return BlockDevice;
    case S_IFCHR:  return CharDevice;
    default:       return UnknownFileKind;
  }
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_kind_of_fd(int fd) {
  struct stat stat;
  if (fstat(fd, &stat) < 0) {
    return -1;
  }

  return moonbitlang_async_file_kind_from_stat(&stat);
}

#endif // #ifndef _WIN32
