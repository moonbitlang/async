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

#else

#include <errno.h>
#include <unistd.h>
#include <sys/wait.h>

typedef int HANDLE;

#ifdef __linux__

#include <linux/version.h>
#include <sys/syscall.h>

#ifndef P_PIDFD
#define P_PIDFD 3
#endif

#endif

#endif

#include <moonbit.h>


MOONBIT_FFI_EXPORT
int moonbitlang_async_get_process_result(HANDLE handle, int32_t pid, int32_t *out) {
#ifdef _WIN32

  BOOL ret = GetExitCodeProcess(handle, out);
  if (ret && *out == STILL_ACTIVE) {
    SetLastError(ERROR_IO_PENDING);
    return -1;
  }
  return ret ? 0 : - 1;

#else

#ifdef __linux__
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 4, 0)

  if (handle >= 0) {
    siginfo_t info;
    info.si_pid = 0;
    int ret = waitid(P_PIDFD, handle, &info, WEXITED | WNOHANG);

    if (ret < 0)
      return -1;

    if (info.si_pid == 0) {
      errno = EAGAIN;
      return -1;
    }

    *out = info.si_status;
    return 0;
  }

#endif // #if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 4, 0)
#endif // #ifdef __linux__

  /* This can be either:
     1. Linux systems without `pidfd` support.
     2. MacOS/BSD
  */
  int wstatus;
  int ret = waitpid(pid, &wstatus, WNOHANG);
  if (ret < 0)
    return -1;

  if (ret == 0) {
    errno = EAGAIN;
    return -1;
  }

  *out = WEXITSTATUS(wstatus);
  return 0;

#endif // #ifdef _WIN32
}


MOONBIT_FFI_EXPORT
HANDLE moonbitlang_async_open_pid_handle(int32_t pid) {
#ifdef _WIN32

  return OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);

#else

#ifdef __linux__
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 4, 0)

  int pidfd = syscall(SYS_pidfd_open, pid, 0);
  if (pidfd < 0 && errno == ENOSYS || errno == EPERM)
    // some container environments do not support `pidfd` even on Linux >= 5.3.0
    errno = 0;

  return pidfd;

#endif // #if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 4, 0)
#endif // #ifdef __linux__

  errno = 0;
  return -1;

#endif // #ifdef _WIN32
}
