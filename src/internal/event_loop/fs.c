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

#ifndef _MSC_VER
#error "Currently only MSVC is supported on Windows"
#endif

#include <windows.h>
#include <stddef.h>

typedef LPWSTR os_string_t;

// #ifdef _WIN32
#else

#include <errno.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/file.h>

#if defined(__linux__)

#include <linux/fs.h>
#include <sys/inotify.h>
#include <sys/syscall.h>

#elif defined(__MACH__)

#include <sys/attr.h>

#endif

typedef int HANDLE;
typedef char *os_string_t;

#define GetLastError() errno
#define SetLastError(err) errno = (err)

// #ifndef _WIN32
#endif


// defined in `detect_file_kind.c`
int32_t moonbitlang_async_kind_of_fd(HANDLE fd);

#ifdef _WIN32
int32_t moonbitlang_async_kind_from_attr(DWORD attrs);
#else
int32_t moonbitlang_async_file_kind_from_stat(struct stat *stat);
#endif

// defined in `thread_pool.c`
MOONBIT_FFI_EXPORT
void *moonbitlang_async_make_job(
  int32_t size,
  void (*free)(void*),
  int32_t (*worker)(void*, int32_t*),
  int32_t (*cancel_handler)(void*)
);

#define MAKE_JOB(name, cancel_handler) (struct name##_job*)moonbitlang_async_make_job(\
  sizeof(struct name##_job),\
  (void (*)(void*))free_##name##_job,\
  (int32_t (*)(void*, int32_t*)) name##_job_worker,\
  (int32_t (*)(void*))cancel_handler\
)


// ===== open job =====

static
HANDLE moonbitlang_async_open_sync(
  os_string_t filename,
  int32_t access_mode,
  int32_t is_async,
  int32_t create_mode,
  int32_t append,
  int32_t sync_mode,
  int32_t permission
) {
#ifdef _WIN32

  static int access_flags[] = {
    GENERIC_READ,
    GENERIC_WRITE,
    GENERIC_READ | GENERIC_WRITE,
    FILE_LIST_DIRECTORY
  };
  static int create_modes[] = { OPEN_EXISTING, TRUNCATE_EXISTING, OPEN_ALWAYS, CREATE_ALWAYS, CREATE_NEW };
  static int sync_flags[] = { 0, FILE_FLAG_WRITE_THROUGH, FILE_FLAG_WRITE_THROUGH };

  DWORD flags =
    FILE_ATTRIBUTE_NORMAL
    | FILE_FLAG_BACKUP_SEMANTICS
    | sync_flags[sync_mode];

  if (is_async)
    flags |= FILE_FLAG_OVERLAPPED;

  DWORD access_flag = access_flags[access_mode];
  if (append)
    access_flag = (access_flag ^ GENERIC_WRITE) | FILE_APPEND_DATA;

  while (1) {
    HANDLE result = CreateFileW(
      filename,
      access_flag, // desired access
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, // shared mode
      NULL, // security attributes
      create_modes[create_mode], // creation
      flags, // flags and attributes. Note that we open files in synchronous mode
      NULL // template file
    );

    if (result != INVALID_HANDLE_VALUE)
      return result;

    // handle error
    int err = GetLastError();
    if (err != ERROR_PIPE_BUSY)
      return INVALID_HANDLE_VALUE;

    // We are trying to open a named pipe, but no pipe instance is available,
    // so wait until any instance is available.
    // This wait is cancellable via `CancelSynchronousIo`.
    if (!WaitNamedPipeW(filename, NMPWAIT_WAIT_FOREVER))
      return INVALID_HANDLE_VALUE;
  }

// #ifdef _WIN32
#else

  static int access_flags[] = { O_RDONLY, O_WRONLY, O_RDWR, O_RDONLY };
  static int create_modes[] = {
    0,
    O_TRUNC,
    O_CREAT,
    O_CREAT | O_TRUNC,
    O_CREAT | O_EXCL
  };
  static int sync_flags[] = { 0, O_DSYNC, O_SYNC };

  int flags =
    access_flags[access_mode]
    | sync_flags[sync_mode]
    | create_modes[create_mode];
  if (append) flags |= O_APPEND;

  return open(filename, flags | O_CLOEXEC, permission);

#endif
}

struct open_job {
  os_string_t filename;
  int access_mode;
  int create_mode;
  int append;
  int sync_mode;
  int permission;
  HANDLE result;
#ifdef _WIN32
  BY_HANDLE_FILE_INFORMATION stat;
#else
  struct stat stat;
#endif
};

static
void free_open_job(struct open_job *job) {
  moonbit_decref(job->filename);
}

static
int32_t open_job_worker(struct open_job *job, int32_t *err_out) {
  job->result = moonbitlang_async_open_sync(
    job->filename,
    job->access_mode,
    job->access_mode == 3, // only handles opened for `ReadDirectoryChangesW` need to be overlapped
    job->create_mode,
    job->append,
    job->sync_mode,
    job->permission
  );

  // Retrieve basic stat about the newly opened file in the same job
  // to save some thread pool communication cost
#ifdef _WIN32

  if (job->result == INVALID_HANDLE_VALUE) {
    *err_out = GetLastError();
    return -1;
  }

  // get the kind of the file
  if (!GetFileInformationByHandle(job->result, &job->stat)) {
    *err_out = GetLastError();
    CloseHandle(job->result);
    return -1;
  }

#else

  if (job->result < 0) {
    *err_out = errno;
    return -1;
  }

  if (fstat(job->result, &job->stat) < 0) {
    *err_out = errno;
    close(job->result);
    return -1;
  }

#endif

  return 0;
}


MOONBIT_FFI_EXPORT
struct open_job *moonbitlang_async_make_open_job(
  os_string_t filename,
  int access_mode,
  int create_mode,
  int append,
  int sync_mode,
  int permission
) {
  struct open_job *job = MAKE_JOB(open, 0);
  job->filename = filename;
  job->access_mode = access_mode;
  job->create_mode = create_mode;
  job->append = append;
  job->sync_mode = sync_mode;
  job->permission = permission;
  return job;
}

MOONBIT_FFI_EXPORT
HANDLE moonbitlang_async_open_job_get_fd(struct open_job *job) {
  return job->result;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_open_job_get_kind(struct open_job *job) {
#ifdef _WIN32
  return moonbitlang_async_kind_from_attr(job->stat.dwFileAttributes);
#else
  return moonbitlang_async_file_kind_from_stat(&job->stat);
#endif
}

MOONBIT_FFI_EXPORT
uint64_t moonbitlang_async_open_job_get_dev_id(struct open_job *job) {
#ifdef _WIN32
  return job->stat.dwVolumeSerialNumber;
#else
  return job->stat.st_dev;
#endif
}

MOONBIT_FFI_EXPORT
uint64_t moonbitlang_async_open_job_get_file_id(struct open_job *job) {
#ifdef _WIN32
  return ((uint64_t)(job->stat.nFileIndexHigh) << 32) | (uint64_t)(job->stat.nFileIndexLow);
#else
  return job->stat.st_ino;
#endif
}

// ===== file kind of fd job, get kind of an existing fd =====
MOONBIT_FFI_EXPORT
struct kind_of_fd_job {
  HANDLE fd;
};

static
void free_kind_of_fd_job(void *obj) {}

static
int32_t kind_of_fd_job_worker(struct kind_of_fd_job *job, int32_t *err_out) {
  int32_t ret = moonbitlang_async_kind_of_fd(job->fd);
  if (ret < 0)
    *err_out = GetLastError();

  return ret;
}

struct kind_of_fd_job *moonbitlang_async_make_kind_of_fd_job(HANDLE fd) {
  struct kind_of_fd_job *job = MAKE_JOB(kind_of_fd, 0);
  job->fd = fd;
  return job;
}


// ===== file kind by path job, get kind of path on file system =====

static
int32_t moonbitlang_async_get_file_kind_by_path(
  os_string_t path,
  int32_t follow_symlink,
  HANDLE parent
) {
#ifdef _WIN32

  if (parent != INVALID_HANDLE_VALUE) {
    SetLastError(ERROR_NOT_SUPPORTED);
    return -1;
  }

  DWORD flags = FILE_ATTRIBUTE_NORMAL | FILE_FLAG_BACKUP_SEMANTICS;
  if (!follow_symlink)
    flags |= FILE_FLAG_OPEN_REPARSE_POINT;

  HANDLE handle = CreateFileW(
    path,
    FILE_READ_ATTRIBUTES, // desired access
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, // shared mode
    NULL, // security attributes
    OPEN_EXISTING, // creation mode
    flags, // flags and attributes
    NULL // template file
  );

  if (handle == INVALID_HANDLE_VALUE)
    return -1;

  int32_t ret = moonbitlang_async_kind_of_fd(handle);
  CloseHandle(handle);

  return ret;

#else

  struct stat stat_obj;
  int ret = fstatat(
    parent < 0 ? AT_FDCWD : parent,
    path,
    &stat_obj,
    follow_symlink ? 0 : AT_SYMLINK_NOFOLLOW
  );
  if (ret < 0)
    return -1;

  return moonbitlang_async_file_kind_from_stat(&stat_obj);

#endif
}

struct file_kind_by_path_job {
  HANDLE parent;
  os_string_t path;
  int follow_symlink;
};

static
void free_file_kind_by_path_job(struct file_kind_by_path_job *job) {
  moonbit_decref(job->path);
}

static
int32_t file_kind_by_path_job_worker(struct file_kind_by_path_job *job, int32_t *err_out) {
  int32_t ret = moonbitlang_async_get_file_kind_by_path(
    job->path,
    job->follow_symlink,
    job->parent
  );

  if (ret < 0)
    *err_out = GetLastError();

  return ret;
}

struct file_kind_by_path_job *moonbitlang_async_make_file_kind_by_path_job(
  HANDLE parent,
  os_string_t path,
  int follow_symlink
) {
  struct file_kind_by_path_job *job = MAKE_JOB(file_kind_by_path, 0);
  job->parent = parent;
  job->path = path;
  job->follow_symlink = follow_symlink;
  return job;
}

// ===== file size job, get size of opened file =====

static
int64_t moonbitlang_async_get_file_size_sync(HANDLE fd) {
#ifdef _WIN32

  LARGE_INTEGER size;
  if (!GetFileSizeEx(fd, &size))
    return -1;

  return size.QuadPart;

#else

  struct stat stat_obj;
  if (fstat(fd, &stat_obj) < 0)
    return -1;

  return stat_obj.st_size;

#endif
}

struct file_size_job {
  HANDLE fd;
  int64_t result;
};

static
void free_file_size_job(struct file_size_job *job) {}

static
int32_t file_size_job_worker(struct file_size_job *job, int32_t *err_out) {
  job->result = moonbitlang_async_get_file_size_sync(job->fd);

  if (job->result < 0) {
    *err_out = GetLastError();
    return -1;
  }

  return 0;
}

struct file_size_job *moonbitlang_async_make_file_size_job(HANDLE fd) {
  struct file_size_job *job = MAKE_JOB(file_size, 0);
  job->fd = fd;
  return job;
}

int64_t moonbitlang_async_get_file_size_result(struct file_size_job *job) {
  return job->result;
}

// ===== file time job, get timestamp of opened file =====
static
int32_t moonbitlang_async_get_file_time_sync(HANDLE fd, void *out) {
#ifdef _WIN32
  BOOL ret = GetFileInformationByHandleEx(
    fd,
    FileBasicInfo,
    out,
    sizeof(FILE_BASIC_INFO)
  );
  return ret ? 0 : -1;
#else
  return fstat(fd, out);
#endif
}

struct file_time_job {
  HANDLE fd;
  void *out;
};

static
void free_file_time_job(struct file_time_job *job) {
  moonbit_decref(job->out);
}

static
int32_t file_time_job_worker(struct file_time_job *job, int32_t *err_out) {
  if (moonbitlang_async_get_file_time_sync(job->fd, job->out) < 0) {
    *err_out = GetLastError();
    return -1;
  }
  return 0;
}

struct file_time_job *moonbitlang_async_make_file_time_job(HANDLE fd, void *out) {
  struct file_time_job *job = MAKE_JOB(file_time, 0);
  job->fd = fd;
  job->out = out;
  return job;
}

// ===== file time by path job, get timestamp of path on file system =====
static
int32_t moonbitlang_async_get_file_time_by_path(
  os_string_t path,
  void *out,
  int32_t follow_symlink
) {
#ifdef _WIN32

  DWORD flags = FILE_ATTRIBUTE_NORMAL | FILE_FLAG_BACKUP_SEMANTICS;
  if (!follow_symlink)
    flags |= FILE_FLAG_OPEN_REPARSE_POINT;

  HANDLE handle = CreateFileW(
    path,
    FILE_READ_ATTRIBUTES, // desired access
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, // shared mode
    NULL, // security attributes
    OPEN_EXISTING, // creation mode
    flags, // flags and attributes
    NULL // template file
  );
  if (handle == INVALID_HANDLE_VALUE)
    return -1;

  int32_t ret = moonbitlang_async_get_file_time_sync(handle, out);
  CloseHandle(handle);
  return ret;

#else

  if (follow_symlink) {
    return stat(path, out);
  } else {
    return lstat(path, out);
  }

#endif
}

struct file_time_by_path_job {
  os_string_t path;
  void *out;
  int follow_symlink;
};

static
void free_file_time_by_path_job(struct file_time_by_path_job *job) {
  moonbit_decref(job->path);
  moonbit_decref(job->out);
}

static
int32_t file_time_by_path_job_worker(struct file_time_by_path_job *job, int32_t *err_out) {
  int32_t ret = moonbitlang_async_get_file_time_by_path(job->path, job->out, job->follow_symlink);
  if (ret < 0)
    *err_out = GetLastError();

  return ret;
}

struct file_time_by_path_job *moonbitlang_async_make_file_time_by_path_job(
  os_string_t path,
  void *out,
  int follow_symlink
) {
  struct file_time_by_path_job *job = MAKE_JOB(file_time_by_path, 0);
  job->path = path;
  job->out = out;
  job->follow_symlink = follow_symlink;
  return job;
}

// ===== chmod job, change permission of file =====

static
int32_t moonbitlang_async_chmod_sync(os_string_t path, int32_t mode) {
#ifdef _WIN32
  SetLastError(ERROR_NOT_SUPPORTED);
  return -1;
#else
  return chmod(path, mode);
#endif
}

struct chmod_job {
  os_string_t path;
  int mode;
};

static
void free_chmod_job(struct chmod_job *job) {
  moonbit_decref(job->path);
}

static
int32_t chmod_job_worker(struct chmod_job *job, int32_t *err_out) {
  if (moonbitlang_async_chmod_sync(job->path, job->mode) < 0) {
    *err_out = GetLastError();
    return -1;
  }
  return 0;
}

struct chmod_job *moonbitlang_async_make_chmod_job(os_string_t path, int mode) {
  struct chmod_job *job = MAKE_JOB(chmod, 0);
  job->path = path;
  job->mode = mode;
  return job;
}

// ===== fsync job, synchronize file modification to disk =====
static
int32_t moonbitlang_async_fsync_sync(HANDLE fd, int32_t only_data) {
#if defined(_WIN32)

  return FlushFileBuffers(fd) ? 0 : -1;

#elif defined(__MACH__)
  // it seems that `fdatasync` is not available on some MacOS versions
  return fsync(fd);

#else

  int32_t ret;
  if (only_data) {
    return fdatasync(fd);
  } else {
    return fsync(fd);
  }

#endif
}

struct fsync_job {
  HANDLE fd;
  int only_data;
};

static
void free_fsync_job(struct fsync_job *job) {}

static
int32_t fsync_job_worker(struct fsync_job *job, int32_t *err_out) {
  if (moonbitlang_async_fsync_sync(job->fd, job->only_data) < 0) {
    *err_out = GetLastError();
    return -1;
  }
  return 0;
}

struct fsync_job *moonbitlang_async_make_fsync_job(HANDLE fd, int only_data) {
  struct fsync_job *job = MAKE_JOB(fsync, 0);
  job->fd = fd;
  job->only_data = only_data;
  return job;
}

// ===== flock job, place advisory lock on a file =====
static
int32_t moonbitlang_async_flock_sync(HANDLE fd, int32_t exclusive) {
#ifdef _WIN32

  OVERLAPPED overlapped;
  memset(&overlapped, 0, sizeof(OVERLAPPED));
  // We want to provide advisory lock here
  // (i.e. only lock operations conflict with each other, raw IO are not affected),
  // because mandatory file lock is not available on Linux/MacOS.
  // However, Windows only provides mandatory file lock.
  // Fortunately, https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-lockfileex
  // explicitly state that locking a region beyond end of file is *not* an error.
  // So, here we lock the last byte in the whole address space to simulate advisory locking,
  // as this region can almost never get touched by normal IO operations.
  overlapped.Offset = 0xfffffffe;
  overlapped.OffsetHigh = 0xffffffff;
  BOOL ret = LockFileEx(
    fd,
    exclusive ? LOCKFILE_EXCLUSIVE_LOCK : 0,
    0, // reserved
    1,
    0,
    &overlapped
  );

  return ret ? 0 : -1;

#else

  return flock(fd, exclusive ? LOCK_EX : LOCK_SH);

#endif
}

struct flock_job {
  HANDLE fd;
  int exclusive;
};

static
void free_flock_job(struct flock_job *job) {}

static
int32_t flock_job_worker(struct flock_job *job, int32_t *err_out) {
  if (moonbitlang_async_flock_sync(job->fd, job->exclusive) < 0) {
    *err_out = GetLastError();
    return -1;
  }
  return 0;
}

struct flock_job *moonbitlang_async_make_flock_job(HANDLE fd, int exclusive) {
  struct flock_job *job = MAKE_JOB(flock, 0);
  job->fd = fd;
  job->exclusive = exclusive;
  return job;
}

// ===== remove job, remove file from file system =====
static
int32_t moonbitlang_async_remove_sync(os_string_t path) {
#ifdef _WIN32
  DWORD attrs = GetFileAttributesW(path);
  if (attrs == INVALID_FILE_ATTRIBUTES)
    return -1;

  BOOL ret;
  // Simulate POSIX behavior on Windows.
  // Maybe we should just merge `@fs.remove` and `@fs.rmdir`?
  if ((attrs & FILE_ATTRIBUTE_DIRECTORY) && (attrs & FILE_ATTRIBUTE_REPARSE_POINT)) {
    ret = RemoveDirectoryW(path);
  } else {
    ret = DeleteFileW(path);
  }

  return ret ? 0 : -1;
#else
  return remove(path);
#endif
}

struct remove_job {
  os_string_t path;
};

static
void free_remove_job(struct remove_job *job) {
  moonbit_decref(job->path);
}

static
int32_t remove_job_worker(struct remove_job *job, int32_t *err_out) {
  if (moonbitlang_async_remove_sync(job->path) < 0) {
    *err_out = GetLastError();
    return -1;
  }
  return 0;
}

struct remove_job *moonbitlang_async_make_remove_job(os_string_t path) {
  struct remove_job *job = MAKE_JOB(remove, 0);
  job->path = path;
  return job;
}

// ===== access job, test permission of file path =====
static
int32_t moonbitlang_async_access_sync(os_string_t path, int32_t amode) {
#ifdef _WIN32

  static int access_modes[] = { 0, GENERIC_READ, GENERIC_WRITE, FILE_EXECUTE };

  HANDLE handle = CreateFileW(
    path,
    access_modes[amode],
    FILE_SHARE_DELETE | FILE_SHARE_READ | FILE_SHARE_WRITE,
    NULL,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL | FILE_FLAG_BACKUP_SEMANTICS,
    NULL
  );
  if (handle == INVALID_HANDLE_VALUE) {
    return -1;
  } else {
    CloseHandle(handle);
    return 0;
  }

#else

  static int access_modes[] = { F_OK, R_OK, W_OK, X_OK };
  return access(path, access_modes[amode]);

#endif
}

struct access_job {
  os_string_t path;
  int amode;
};

static
void free_access_job(struct access_job *job) {
  moonbit_decref(job->path);
}

static
int32_t access_job_worker(struct access_job *job, int32_t *err_out) {
  if (moonbitlang_async_access_sync(job->path, job->amode) < 0) {
    *err_out = GetLastError();
    return -1;
  }
  return 0;
}

struct access_job *moonbitlang_async_make_access_job(os_string_t path, int amode) {
  struct access_job *job = MAKE_JOB(access, 0);
  job->path = path;
  job->amode = amode;
  return job;
}

// ===== rename job, rename file =====
static
int32_t moonbitlang_async_rename_sync(os_string_t old_path, os_string_t new_path, int32_t replace) {
#ifdef _WIN32

  HANDLE handle = CreateFileW(
    old_path,
    DELETE,
    FILE_SHARE_DELETE | FILE_SHARE_READ | FILE_SHARE_WRITE,
    NULL,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL | FILE_FLAG_BACKUP_SEMANTICS,
    NULL
  );

  if (handle == INVALID_HANDLE_VALUE)
    return -1;

  int new_path_len = Moonbit_array_length(new_path);
  int buffer_size = sizeof(FILE_RENAME_INFO) + new_path_len * 2 + 2;
  FILE_RENAME_INFO *info = (FILE_RENAME_INFO*)malloc(buffer_size);

  // 3 = FILE_RENAME_REPLACE_IF_EXISTS | FILE_RENAME_POSIX_SEMANTICS
  info->Flags = replace ? 3 : 0;
  info->RootDirectory = NULL;
  info->FileNameLength = new_path_len * 2;
  memcpy(info->FileName, new_path, new_path_len * 2);
  info->FileName[new_path_len] = 0;

  BOOL ret = SetFileInformationByHandle(handle, FileRenameInfoEx, info, buffer_size);

  CloseHandle(handle);
  free(info);

  if (ret)
    return 0;

  if (GetLastError() != ERROR_INVALID_PARAMETER)
    return -1;

  // fallback on older systems

  ret = MoveFileExW(
    old_path,
    new_path,
    MOVEFILE_COPY_ALLOWED | (replace ? MOVEFILE_REPLACE_EXISTING : 0)
  );
  return ret ? 0 : -1;

#elif defined(__MACH__)

  return renameatx_np(
    AT_FDCWD, old_path,
    AT_FDCWD, new_path,
    replace ? 0 : RENAME_EXCL
  );

#elif defined(__linux__)

  return syscall(
    SYS_renameat2,
    AT_FDCWD, old_path,
    AT_FDCWD, new_path,
    replace ? 0 : RENAME_NOREPLACE
  );

#else

  SetLastError(ENOSYS);
  return -1;

#endif
}

struct rename_job {
  os_string_t old_path;
  os_string_t new_path;
  int32_t replace;
};

static
void free_rename_job(struct rename_job *job) {
  moonbit_decref(job->old_path);
  moonbit_decref(job->new_path);
}

static
int32_t rename_job_worker(struct rename_job *job, int32_t *err_out) {
  if (moonbitlang_async_rename_sync(job->old_path, job->new_path, job->replace) < 0) {
    *err_out = GetLastError();
    return -1;
  }
  return 0;
}

struct rename_job *moonbitlang_async_make_rename_job(
  os_string_t old_path,
  os_string_t new_path,
  int32_t replace
) {
  struct rename_job *job = MAKE_JOB(rename, 0);
  job->old_path = old_path;
  job->new_path = new_path;
  job->replace = replace;
  return job;
}

// ===== symlink job, create symbolic link =====
#ifdef _WIN32
typedef struct {
    USHORT SubstituteNameOffset;
    USHORT SubstituteNameLength;
    USHORT PrintNameOffset;
    USHORT PrintNameLength;
    WCHAR  PathBuffer[1];
} MOUNT_POINT_REPARSE_BUFFER;

typedef struct {
  ULONG ReparseTag;
  USHORT ReparseDataLength;
  USHORT Reserved;
  MOUNT_POINT_REPARSE_BUFFER MountPointReparseBuffer;
} REPARSE_DATA_BUFFER;
#endif

static
int32_t moonbitlang_async_symlink_sync(os_string_t target, os_string_t path, int32_t force_symlink) {
#ifdef _WIN32

  BOOL ok;

  int target_len = Moonbit_array_length(target);

  DWORD attrs = GetFileAttributesW(target);
  BOOL is_dir = attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY);

  // create NTFS junction if possible
  if (force_symlink)
    goto symlink_fallback;

  if (!is_dir)
    goto symlink_fallback;

  if (wcsncmp(target, L"\\??\\", 4) == 0 || wcsncmp(target, L"\\\\?\\", 4) == 0) {
    target += 4;
    target_len -= 4;
  }

  if (
    target_len >= 3
    && ('a' <= target[0] && target[0] <= 'z' || 'A' <= target[0] && target[0] <= 'Z')
    && target[1] == ':'
    && (target[2] == '\\' || target[2] == '/')
  ) {
    // normal absolute path
  } else if (wcsncmp(target, L"\\", 2) == 0) {
    // UNC path for network resource, does not support junction
    goto symlink_fallback;
  } else {
    // relaive path, does not support junction
    goto symlink_fallback;
  }

  if (!CreateDirectoryW(path, NULL))
    return -1;

  HANDLE link = CreateFileW(
    path,
    GENERIC_WRITE,
    0,
    NULL,
    OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS,
    NULL
  );
  if (link == INVALID_HANDLE_VALUE) {
    int32_t err = GetLastError();
    RemoveDirectoryW(path);
    SetLastError(err);
    return -1;
  }

  DWORD substitute_name_len =
    2 * target_len
    + 8 // NT path "\??\" prefix for substitute path
  ;
  DWORD print_name_len = 2 * target_len;

  DWORD path_buffer_length =
    substitute_name_len
    + print_name_len
    + 4 // NUL terminator for substitute path and print path
  ;

  DWORD reparse_buffer_length =
    offsetof(MOUNT_POINT_REPARSE_BUFFER, PathBuffer)
    + path_buffer_length;

  DWORD buffer_size =
    offsetof(REPARSE_DATA_BUFFER, MountPointReparseBuffer)
    + reparse_buffer_length;

  REPARSE_DATA_BUFFER *buf = (REPARSE_DATA_BUFFER*)malloc(buffer_size);
  buf->ReparseTag = IO_REPARSE_TAG_MOUNT_POINT;
  buf->ReparseDataLength = reparse_buffer_length;
  buf->Reserved = 0;
  buf->MountPointReparseBuffer.SubstituteNameOffset = 0;
  buf->MountPointReparseBuffer.SubstituteNameLength = substitute_name_len;
  memcpy(
    buf->MountPointReparseBuffer.PathBuffer,
    L"\\??\\",
    8
  );
  memcpy(
    buf->MountPointReparseBuffer.PathBuffer + 4,
    target,
    target_len * 2 + 2
  );
  for (WCHAR *ptr = buf->MountPointReparseBuffer.PathBuffer + 4; *ptr; ++ptr) {
    // substitute path does not support forward slash
    if (*ptr == L'/')
      *ptr = L'\\';
  }
  buf->MountPointReparseBuffer.PrintNameOffset = substitute_name_len + 2;
  buf->MountPointReparseBuffer.PrintNameLength = print_name_len;
  memcpy(
    buf->MountPointReparseBuffer.PathBuffer + 5 + target_len,
    // avoid substituting forward slash twice, reuse the substituted result
    buf->MountPointReparseBuffer.PathBuffer + 4,
    target_len * 2 + 2
  );

  DWORD bytes_returned = 0;
  ok = DeviceIoControl(
    link,
    FSCTL_SET_REPARSE_POINT,
    buf,
    buffer_size,
    NULL,
    0,
    &bytes_returned,
    NULL
  );
  int err = GetLastError();
  free(buf);
  CloseHandle(link);

  if (!ok) {
    RemoveDirectoryW(path);
    if (err == ERROR_INVALID_PARAMETER) {
      // this is mainly for handling non-NTFS volume.
      // There are other cases that will also generate `ERROR_INVALID_PARAMETER`,
      // such as invalid character in path.
      // But for those cases, the symlink fallback path will give a similar error,
      // so the net result is still the same.
      goto symlink_fallback;
    }

    SetLastError(err);
    return -1;
  }

  return 0;

symlink_fallback:

  ok = CreateSymbolicLinkW(
    path,
    target,
    is_dir ? SYMBOLIC_LINK_FLAG_DIRECTORY : 0
  );

  return ok ? 0 : -1;

#else

  return symlink(target, path);

#endif
}

struct symlink_job {
  os_string_t target;
  os_string_t path;
  int32_t force_symlink;
};

static
void free_symlink_job(struct symlink_job *job) {
  moonbit_decref(job->target);
  moonbit_decref(job->path);
}

static
int32_t symlink_job_worker(struct symlink_job *job, int32_t *err_out) {
  if (moonbitlang_async_symlink_sync(job->target, job->path, job->force_symlink) < 0) {
    *err_out = GetLastError();
    return -1;
  }
  return 0;
}

struct symlink_job *moonbitlang_async_make_symlink_job(
  os_string_t target,
  os_string_t path,
  int32_t force_symlink
) {
  struct symlink_job *job = MAKE_JOB(symlink, 0);
  job->target = target;
  job->path = path;
  job->force_symlink = force_symlink;
  return job;
}

// ===== mkdir job, create new directory =====
static
int32_t moonbitlang_async_mkdir_sync(os_string_t path, int32_t permission) {
#ifdef _WIN32

  return CreateDirectoryW(path, NULL) ? 0 : -1;

#else

  return mkdir(path, permission);

#endif
}

struct mkdir_job {
  os_string_t path;
  int32_t permission;
};

static
void free_mkdir_job(struct mkdir_job *job) {
  moonbit_decref(job->path);
}

static
int32_t mkdir_job_worker(struct mkdir_job *job, int32_t *err_out) {
  if (moonbitlang_async_mkdir_sync(job->path, job->permission) < 0) {
    *err_out = GetLastError();
    return -1;
  }
  return 0;
}

struct mkdir_job *moonbitlang_async_make_mkdir_job(os_string_t path, int32_t permission) {
  struct mkdir_job *job = MAKE_JOB(mkdir, 0);
  job->path = path;
  job->permission = permission;
  return job;
}

// ===== rmdir job, remove directory =====
static
int32_t moonbitlang_async_rmdir_sync(os_string_t path) {
#ifdef _WIN32

  return RemoveDirectoryW(path) ? 0 : -1;

#else

  return rmdir(path);

#endif
}

struct rmdir_job {
  os_string_t path;
};

static
void free_rmdir_job(struct rmdir_job *job) {
  moonbit_decref(job->path);
}

static
int32_t rmdir_job_worker(struct rmdir_job *job, int32_t *err_out) {
  if (moonbitlang_async_rmdir_sync(job->path) < 0) {
    *err_out = GetLastError();
    return -1;
  }
  return 0;
}

struct rmdir_job *moonbitlang_async_make_rmdir_job(os_string_t path) {
  struct rmdir_job *job = MAKE_JOB(rmdir, 0);
  job->path = path;
  return job;
}

// ===== readdir job, read directory entry =====
static
int32_t moonbitlang_async_readdir_sync(HANDLE dir, void *out, int32_t len, int32_t restart) {
#ifdef _WIN32
  DWORD kind = restart ?  FileIdBothDirectoryRestartInfo : FileIdBothDirectoryInfo;
  if (!GetFileInformationByHandleEx(dir, kind, out, len)) {
    if (GetLastError() == ERROR_NO_MORE_FILES)
      return 0;
    else
      return -1;
  }

  // `GetFileInformationByHandleEx` does not support a total length
  return len;

#elif defined(__linux__)

  if (restart && lseek(dir, 0, SEEK_SET) < 0)
    return -1;

  return syscall(SYS_getdents64, dir, out, len);

#elif defined(__MACH__)

  if (restart && lseek(dir, 0, SEEK_SET) < 0)
    return -1;

  struct attrlist attr_spec = {
    ATTR_BIT_MAP_COUNT,
    0, // reserved
    ATTR_CMN_NAME | ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_OBJTYPE | ATTR_CMN_FILEID, // commonattr
    0, // volattr
    0, // dirattr
    0, // fileattr
    0 // forkattr
  };
  return getattrlistbulk(dir, &attr_spec, out, len, 0);

#else

  SetLastError(ENOSYS);
  return -1;

#endif
}

struct readdir_job {
  HANDLE dir;
  void *out;
  int32_t len;
  int32_t restart;
};

static
void free_readdir_job(struct readdir_job *job) {}

static
int32_t readdir_job_worker(struct readdir_job *job, int32_t *err_out) {
  int32_t ret = moonbitlang_async_readdir_sync(job->dir, job->out, job->len, job->restart);
  if (ret < 0)
    *err_out = GetLastError();

  return ret;
}

struct readdir_job *moonbitlang_async_make_readdir_job(
  HANDLE dir,
  void *out,
  int32_t len,
  int32_t restart
) {
  struct readdir_job *job = MAKE_JOB(readdir, 0);
  job->dir = dir;
  job->out = out;
  job->len = len;
  job->restart = restart;
  return job;
}

// ===== realpath job, get canonical representation of a path =====
static
os_string_t moonbitlang_async_realpath_sync(os_string_t path, os_string_t buf, int32_t buf_len) {
#ifdef _WIN32
  HANDLE file = CreateFileW(
    path,
    0,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    NULL,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL | FILE_FLAG_BACKUP_SEMANTICS,
    NULL
  );
  if (file == INVALID_HANDLE_VALUE)
    return NULL;

  DWORD len = GetFinalPathNameByHandleW(
    file,
    buf,
    buf ? buf_len : 0,
    FILE_NAME_NORMALIZED | VOLUME_NAME_DOS
  );

  if (len >= buf_len) {
    // include the extra NUL terminator
    buf = malloc((len + 1) * sizeof(WCHAR));
    len = GetFinalPathNameByHandleW(file, buf, len, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
  }
  CloseHandle(file);
  return len ? buf : NULL;

#else

  return realpath(path, 0);

#endif
}

#ifdef _WIN32
#define REALPATH_JOB_BUFFER_LENGTH 1024
#endif

struct realpath_job {
  os_string_t path;
  os_string_t result;
#ifdef _WIN32
  // avoid some allocation in the simple case
  WCHAR buf[REALPATH_JOB_BUFFER_LENGTH];
#endif
};

static
void free_realpath_job(struct realpath_job *job) {
  moonbit_decref(job->path);
#ifdef _WIN32
  if (job->result && job->result != job->buf)
    free(job->result);
#else
  if (job->result)
    free(job->result);
#endif
}

static
int32_t realpath_job_worker(struct realpath_job *job, int32_t *err_out) {
#ifdef _WIN32
  os_string_t buf = job->buf;
  int32_t buf_len = REALPATH_JOB_BUFFER_LENGTH;
#else
  os_string_t buf = 0;
  int32_t buf_len = 0;
#endif

  job->result = moonbitlang_async_realpath_sync(job->path, buf, buf_len);
  if (!job->result) {
    *err_out = GetLastError();
    return -1;
  }
  return 0;
}

struct realpath_job *moonbitlang_async_make_realpath_job(os_string_t path) {
  struct realpath_job *job = MAKE_JOB(realpath, 0);
  job->path = path;
  job->result = 0;
  return job;
}

char *moonbitlang_async_get_realpath_result(struct realpath_job *job) {
#ifdef _WIN32
  if (wcsncmp(job->result, L"\\\\?\\UNC\\", 8) == 0) {
    job->result[6] = L'\\';
    return (char*)job->result + 6 * sizeof(WCHAR);
  }
  else if (wcsncmp(job->result, L"\\\\?\\", 4) == 0)
    return (char*)job->result + 4 * sizeof(WCHAR);
  else
    return (char*)job->result + 8;
#else
  return job->result;
#endif
}


#ifndef _WIN32
// ===== inotify_add_watch job, add path to watch with inotify =====
struct inotify_add_watch_job {
  HANDLE inotify;
  os_string_t path;
  int32_t is_dir;
};

static
void free_inotify_add_watch_job(struct inotify_add_watch_job *job) {
  moonbit_decref(job->path);
}

static
int32_t inotify_add_watch_job_worker(struct inotify_add_watch_job *job, int32_t *err_out) {
#ifdef __linux__

  uint32_t flags = job->is_dir
    ? IN_CREATE | IN_MOVED_FROM | IN_MOVED_TO | IN_DELETE
    : IN_MODIFY;

  int32_t ret = inotify_add_watch(job->inotify, job->path, flags);
  if (ret < 0)
    *err_out = errno;
  return ret;

#else

  *err_out = ENOSYS;
  return 0;

#endif
}

MOONBIT_FFI_EXPORT
struct inotify_add_watch_job *moonbitlang_async_make_inotify_add_watch_job(
  HANDLE inotify,
  os_string_t path,
  int32_t is_dir
) {
  struct inotify_add_watch_job *job = MAKE_JOB(inotify_add_watch, 0);

  job->inotify = inotify;
  job->path = path;
  job->is_dir = is_dir;

  return job;
}

#endif // #ifndef _WIN32, `inotify_add_watch` job
