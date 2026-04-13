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

#include <stdint.h>
#include <moonbit.h>

#ifdef _WIN32

#include <winsock2.h>
#include <windows.h>

#else

#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

#endif


#ifdef _WIN32

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_fd_is_valid(HANDLE handle) {
  return handle == INVALID_HANDLE_VALUE;
}

MOONBIT_FFI_EXPORT
HANDLE moonbitlang_async_get_invalid_handle() {
  return INVALID_HANDLE_VALUE;
}


#else
MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_fd_is_valid(int fd) {
  return fd < 0;
}
#endif

#ifdef _WIN32
MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_close_fd(HANDLE handle, int32_t is_socket) {
  if (is_socket) {
    return 0 == closesocket((SOCKET)handle);
  } else {
    return CloseHandle(handle);
  }
}
#endif

#ifndef _WIN32

int moonbitlang_async_fd_is_nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0)
    return flags;

  return (flags & O_NONBLOCK) > 0;
}

int moonbitlang_async_set_blocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0) return flags;

  if (flags & O_NONBLOCK) {
    if (fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) < 0)
      return -1;
  }

  return 0;
}

int moonbitlang_async_set_nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0) return flags;

  if (!(flags & O_NONBLOCK)) {
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0)
      return -1;
  }

  return 0;
}

int moonbitlang_async_set_cloexec(int fd) {
  int flags = fcntl(fd, F_GETFD);
  if (flags < 0) return flags;

  if (!(flags & FD_CLOEXEC)) {
    if (fcntl(fd, F_SETFD, flags | FD_CLOEXEC) < 0)
      return -1;
  }

  return 0;
}

#endif

#ifdef _WIN32

MOONBIT_FFI_EXPORT
HANDLE moonbitlang_async_create_named_pipe_server(LPCWSTR name, int32_t is_async) {
  DWORD flags = PIPE_ACCESS_OUTBOUND | FILE_FLAG_FIRST_PIPE_INSTANCE;
  if (is_async)
    flags |= FILE_FLAG_OVERLAPPED;

  return CreateNamedPipeW(
    name,
    flags,
    PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
    PIPE_UNLIMITED_INSTANCES,
    1024,
    1024,
    0,
    NULL
  );
}

MOONBIT_FFI_EXPORT
HANDLE moonbitlang_async_create_named_pipe_client(LPCWSTR name, int32_t is_async) {
  return CreateFileW(
    name,
    GENERIC_READ,
    0,
    NULL,
    OPEN_EXISTING,
    is_async ? FILE_FLAG_OVERLAPPED : 0,
    NULL
  );
}

#else

int moonbitlang_async_pipe(int *fds) {
  if (pipe(fds) < 0)
    return -1;

  for (int i = 0; i < 2; ++i) {
    if (moonbitlang_async_set_cloexec(fds[i]) < 0)
      return -1;
  }

  return 0;
}

#endif

#ifdef _WIN32
typedef FILE_BASIC_INFO file_time_t;
#else
typedef struct stat     file_time_t;
#endif

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_sizeof_file_time() {
  return sizeof(file_time_t);
}

#ifdef _WIN32

#define GET_FILETIME_SEC(stat, kind) ((stat)->kind##Time.QuadPart / 10000000)
#define GET_FILETIME_NSEC(stat, kind) (((stat)->kind##Time.QuadPart % 10000000) * 100)

#elif defined(__MACH__)

#define GET_STAT_TIMESTAMP(statp, kind) (statp)->st_##kind##timespec

#else

#define GET_STAT_TIMESTAMP(statp, kind) (statp)->st_##kind##tim

#endif

MOONBIT_FFI_EXPORT
int64_t moonbitlang_async_get_atime_sec(file_time_t *stat) {
#ifdef _WIN32
  return GET_FILETIME_SEC(stat, LastAccess);
#else
  return GET_STAT_TIMESTAMP(stat, a).tv_sec;
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_get_atime_nsec(file_time_t *stat) {
#ifdef _WIN32
  return GET_FILETIME_NSEC(stat, LastAccess);
#else
  return GET_STAT_TIMESTAMP(stat, a).tv_nsec;
#endif
}

MOONBIT_FFI_EXPORT
int64_t moonbitlang_async_get_mtime_sec(file_time_t *stat) {
#ifdef _WIN32
  return GET_FILETIME_SEC(stat, LastWrite);
#else
  return GET_STAT_TIMESTAMP(stat, m).tv_sec;
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_get_mtime_nsec(file_time_t *stat) {
#ifdef _WIN32
  return GET_FILETIME_NSEC(stat, LastWrite);
#else
  return GET_STAT_TIMESTAMP(stat, m).tv_nsec;
#endif
}

MOONBIT_FFI_EXPORT
int64_t moonbitlang_async_get_ctime_sec(file_time_t *stat) {
#ifdef _WIN32
  return GET_FILETIME_SEC(stat, Change);
#else
  return GET_STAT_TIMESTAMP(stat, c).tv_sec;
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_get_ctime_nsec(file_time_t *stat) {
#ifdef _WIN32
  return GET_FILETIME_NSEC(stat, Change);
#else
  return GET_STAT_TIMESTAMP(stat, c).tv_nsec;
#endif
}
