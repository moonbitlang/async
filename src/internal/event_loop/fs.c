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

#define _GNU_SOURCE

#include <stdint.h>
#include <moonbit.h>

#ifdef _WIN32

#ifndef _MSC_VER
#error "Currently only MSVC is supported on Windows"
#endif

#include <winsock2.h>
#include <windows.h>
#include <winternl.h>
#include <stddef.h>
#include <stdio.h>

#if _WIN32_WINNT >= 0x0602
#include <pathcch.h>
#pragma comment(lib, "Pathcch.lib")
#pragma comment(lib, "ntdll.lib")
#endif

typedef LPWSTR os_string_t;

// #ifdef _WIN32
#else

#include <errno.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/file.h>

#if defined(__linux__)

#include <linux/fs.h>
#include <sys/inotify.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>

#elif defined(__MACH__)

#include <sys/stat.h>
#include <sys/attr.h>
#include <sys/vnode.h>
#include <malloc/malloc.h>

#endif

typedef int HANDLE;
typedef char *os_string_t;

#define GetLastError() errno
#define SetLastError(err) errno = (err)

#define ERROR_INVALID_PARAMETER EINVAL

// #ifndef _WIN32
#endif


// defined in `thread_pool.c`
MOONBIT_FFI_EXPORT
void *moonbit_rt_make_job(
  int32_t size,
  void (*free)(void*),
  int32_t (*worker)(void*, int32_t*),
  int32_t (*cancel_handler)(void*)
);

#define MAKE_JOB(name, cancel_handler) (struct name##_job*)moonbit_rt_make_job(\
  sizeof(struct name##_job),\
  (void (*)(void*))free_##name##_job,\
  (int32_t (*)(void*, int32_t*)) name##_job_worker,\
  (int32_t (*)(void*))cancel_handler\
)

void *moonbit_rt_get_current_worker();
#define moonbitlang_async_get_current_worker moonbit_rt_get_current_worker

int32_t moonbit_rt_enter_cancellable_region(void *worker);
#define moonbitlang_async_enter_cancellable_region moonbit_rt_enter_cancellable_region

void moonbit_rt_leave_cancellable_region(void *worker);
#define moonbitlang_async_leave_cancellable_region moonbit_rt_leave_cancellable_region

#ifdef _WIN32

static
HMODULE ntdll_handle = NULL;

#define DECLARE_NT_FUNCTION_GENERIC(ret, name, args, FAILURE, RETURN, ...) \
  typedef ret (NTAPI *pfn_##name)(__VA_ARGS__); \
  static ret NTAPI name##_loader(__VA_ARGS__); \
  static pfn_##name name = & name##_loader; \
  static ret NTAPI name##_loader(__VA_ARGS__) { \
    if (!ntdll_handle) { \
      ntdll_handle = GetModuleHandleW(L"ntdll"); \
      if (!ntdll_handle) FAILURE; \
    } \
    pfn_##name f = (pfn_##name)GetProcAddress(ntdll_handle, #name); \
    if (!f) FAILURE; \
    name = f; \
    RETURN f args; \
  }

#ifndef STATUS_PROCEDURE_NOT_FOUND
#define STATUS_PROCEDURE_NOT_FOUND ((NTSTATUS)0xC000007AL)
#endif

#define DECLARE_NT_FUNCTION_WITH_STATUS(name, args, ...) \
  DECLARE_NT_FUNCTION_GENERIC(NTSTATUS, name, args, return STATUS_PROCEDURE_NOT_FOUND, return, __VA_ARGS__)

#define DECLARE_VOID_NT_FUNCTION(name, args, ...) \
  DECLARE_NT_FUNCTION_GENERIC(VOID, name, args, return, (void), __VA_ARGS__)

#define DECLARE_NT_FUNCTION(ret, name, err_ret, args, ...) \
  DECLARE_NT_FUNCTION_GENERIC(ret, name, args, return err_ret, return, __VA_ARGS__)

DECLARE_NT_FUNCTION(
  ULONG, RtlIsDosDeviceName_U,
  FALSE, (DosFileName),
  PCWSTR DosFileName
)

// `RTL_RELATIVE_NAME_U` is not exposed by the Windows SDK's `winternl.h`.
typedef struct _RTL_RELATIVE_NAME_U {
  UNICODE_STRING RelativeName;
  HANDLE ContainingDirectory;
  PVOID CurDirRef;
} RTL_RELATIVE_NAME_U, *PRTL_RELATIVE_NAME_U;

DECLARE_NT_FUNCTION_WITH_STATUS(
  RtlDosPathNameToRelativeNtPathName_U_WithStatus, (DosFileName, NtFileName, FilePart, RelativeName),
  PCWSTR DosFileName,
  PUNICODE_STRING NtFileName,
  PWSTR *FilePart,
  PRTL_RELATIVE_NAME_U RelativeName
)

DECLARE_VOID_NT_FUNCTION(
  RtlReleaseRelativeName, (RelativeName),
  PRTL_RELATIVE_NAME_U RelativeName
)

#endif


// ===== generic open function =====

enum OpenAccessMode {
  ReadOnly = 0,
  WriteOnly = 1,
  ReadWrite = 2,
  ListDirectory = 3,
  ReadAttributes = 4,
  DeleteAccess = 5
};

struct OpenOption {
  enum OpenAccessMode access_mode;
  int32_t follow_symlink;
  int32_t is_async;
  int32_t create_mode;
  int32_t append;
  int32_t sync_mode;
  int32_t permission;
};

static
HANDLE moonbitlang_async_open_sync(
  HANDLE parent,
  os_string_t filename,
  struct OpenOption *options
) {
  void *worker = moonbitlang_async_get_current_worker();

#ifdef _WIN32

  static ACCESS_MASK access_flags[] = {
    GENERIC_READ,
    GENERIC_WRITE | FILE_READ_ATTRIBUTES,
    GENERIC_READ | GENERIC_WRITE,
    FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES,
    FILE_READ_ATTRIBUTES,
    DELETE
  };
  static ULONG create_modes[] = {
    FILE_OPEN,
    FILE_OVERWRITE,
    FILE_OPEN_IF,
    FILE_OVERWRITE_IF,
    FILE_CREATE
  };
  static ULONG sync_flags[] = { 0, FILE_WRITE_THROUGH, FILE_WRITE_THROUGH };

  ULONG create_options = sync_flags[options->sync_mode];
  if (!options->is_async)
    create_options |= FILE_SYNCHRONOUS_IO_NONALERT;

  if (!options->follow_symlink)
    create_options |= FILE_OPEN_REPARSE_POINT;

  ACCESS_MASK access_flag = access_flags[options->access_mode];
  if (options->append)
    access_flag = (access_flag ^ GENERIC_WRITE) | FILE_APPEND_DATA;
  if (!options->is_async)
    access_flag |= SYNCHRONIZE;

  int relative_open = parent != INVALID_HANDLE_VALUE;
  UNICODE_STRING nt_name = { 0 };
  RTL_RELATIVE_NAME_U relative_name = { 0 };
  PUNICODE_STRING object_name = &nt_name;
  HANDLE root_directory = parent;
  NTSTATUS nt_status;

  if (relative_open) {
    // With an explicit parent, `filename` is already an NT relative path.
    int filename_len = lstrlenW(filename);
    if (filename_len > 32767) {
      SetLastError(ERROR_FILENAME_EXCED_RANGE);
      return INVALID_HANDLE_VALUE;
    }
    nt_name.Length = (USHORT)(filename_len * sizeof(WCHAR));
    nt_name.MaximumLength = nt_name.Length;
    nt_name.Buffer = filename;
  } else {
    nt_status = RtlDosPathNameToRelativeNtPathName_U_WithStatus(
      filename,
      &nt_name,
      NULL,
      &relative_name
    );
    if (!NT_SUCCESS(nt_status)) {
      SetLastError(RtlNtStatusToDosError(nt_status));
      return INVALID_HANDLE_VALUE;
    }

    root_directory = NULL;
    if (relative_name.RelativeName.Length != 0) {
      object_name = &relative_name.RelativeName;
      root_directory = relative_name.ContainingDirectory;
    }
  }

  OBJECT_ATTRIBUTES object_attributes;
  InitializeObjectAttributes(
    &object_attributes,
    object_name,
    OBJ_CASE_INSENSITIVE,
    root_directory,
    NULL
  );

  HANDLE result = INVALID_HANDLE_VALUE;
  int err = ERROR_SUCCESS;

  while (1) {
    IO_STATUS_BLOCK io_status;

    if (moonbitlang_async_enter_cancellable_region(worker)) {
      err = ERROR_OPERATION_ABORTED;
      break;
    }

    result = INVALID_HANDLE_VALUE;
    nt_status = NtCreateFile(
      &result,
      access_flag, // desired access
      &object_attributes,
      &io_status,
      NULL, // allocation size
      FILE_ATTRIBUTE_NORMAL,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, // shared mode
      create_modes[options->create_mode], // creation
      create_options,
      NULL, // extended attributes
      0 // extended attributes length
    );
    moonbitlang_async_leave_cancellable_region(worker);

    if (NT_SUCCESS(nt_status))
      break;

    // handle error
    result = INVALID_HANDLE_VALUE;
    err = RtlNtStatusToDosError(nt_status);
    if (err != ERROR_PIPE_BUSY || relative_open)
      break;

    // We are trying to open a named pipe, but no pipe instance is available,
    // so wait until any instance is available.
    // This wait is cancellable via `CancelSynchronousIo`.
    if (moonbitlang_async_enter_cancellable_region(worker)) {
      err = ERROR_OPERATION_ABORTED;
      break;
    }

    BOOL status = WaitNamedPipeW(filename, NMPWAIT_WAIT_FOREVER);
    moonbitlang_async_leave_cancellable_region(worker);

    if (!status) {
      err = GetLastError();
      break;
    }
  }

  if (!relative_open) {
    RtlReleaseRelativeName(&relative_name);
    RtlFreeUnicodeString(&nt_name);
  }

  if (result == INVALID_HANDLE_VALUE)
    SetLastError(err);
  return result;

// #ifdef _WIN32
#else

  static int access_flags[] = {
    O_RDONLY,
    O_WRONLY,
    O_RDWR,
    O_RDONLY,
    O_RDONLY,
    O_RDONLY
  };
  static int create_modes[] = {
    0,
    O_TRUNC,
    O_CREAT,
    O_CREAT | O_TRUNC,
    O_CREAT | O_EXCL
  };
  static int sync_flags[] = { 0, O_DSYNC, O_SYNC };

  int flags =
    access_flags[options->access_mode]
    | sync_flags[options->sync_mode]
    | create_modes[options->create_mode]
    | O_CLOEXEC;
  if (options->append) flags |= O_APPEND;

  if (!options->follow_symlink)
# ifdef __linux__
    flags |= O_NOFOLLOW;
# elif defined(__MACH__)
    flags |= O_SYMLINK;
# else
    ;
# endif

  if (moonbitlang_async_enter_cancellable_region(worker)) {
    errno = EINTR;
    return -1;
  }

  int dirfd = parent < 0 ? AT_FDCWD : parent;
  int ret = openat(dirfd, filename, flags, options->permission);

#ifdef __linux__
  if (ret < 0 && errno == ELOOP && !options->follow_symlink)
    ret = openat(dirfd, filename, flags | O_PATH, options->permission);
#endif

  moonbitlang_async_leave_cancellable_region(worker);
  return ret;

#endif
}

// ===== stat related helpers =====

#define STAT_FILE_KIND 0x0001
#define STAT_FILE_SIZE 0x0002
#define STAT_DEVICE_ID 0x0004
#define STAT_FILE_ID   0x0008

#define STAT_ACCESS_TIME 0x0010
#define STAT_MODIFY_TIME 0x0020
#define STAT_CHANGE_TIME 0x0040
#define STAT_CREATE_TIME 0x0080

#define STAT_SUPPORTED_PROPERTY_MASK 0x00FF

enum FileKind {
  UnknownFileKind = 0,
  Regular = 1,
  Directory = 2,
  SymLink = 3,
  Socket = 4,
  Pipe = 5,
  BlockDevice = 6,
  CharDevice = 7,
  Console = 8
};

struct FileSpec {
  enum { BY_HANDLE, BY_PATH } kind; 
  union {
    HANDLE fd;
    struct {
      os_string_t path;
      HANDLE parent;
      int32_t follow_symlink;
    } path_spec;
  };
};

struct StatOutputBuffer {
  uint32_t length;
  uint32_t returned_mask;
  uint64_t properties[];
};

#ifdef __linux__

// `glibc` does not expose many statx-related constants

#ifndef AT_EMPTY_PATH
#define AT_EMPTY_PATH 0x1000
#endif

#ifndef AT_SYMLINK_NOFOLLOW
#define AT_SYMLINK_NOFOLLOW 0x100
#endif

#ifndef AT_STATX_SYNC_AS_STAT
#define AT_STATX_SYNC_AS_STAT 0x0000
#endif

#ifndef STATX_TYPE
#define STATX_TYPE 0x00000001U
#endif

#ifndef STATX_SIZE
#define STATX_SIZE 0x00000200U
#endif

#ifndef STATX_INO
#define STATX_INO  0x00000100U
#endif

#ifndef STATX_ATIME
#define STATX_ATIME 0x00000020U
#endif

#ifndef STATX_MTIME
#define STATX_MTIME 0x00000040U
#endif

#ifndef STATX_CTIME
#define STATX_CTIME 0x00000080U
#endif

#ifndef STATX_BTIME
#define STATX_BTIME	0x00000800U	
#endif

struct linux_statx_timestamp {
  int64_t   tv_sec;
  uint32_t  tv_nsec;
  int32_t   __reserved;
};

struct linux_statx {
   uint32_t stx_mask;
   uint32_t stx_blksize;
   uint64_t stx_attributes;
   uint32_t stx_nlink;
   uint32_t stx_uid;
   uint32_t stx_gid;
   uint16_t stx_mode;
   uint64_t stx_ino;
   uint64_t stx_size;
   uint64_t stx_blocks;
   uint64_t stx_attributes_mask;

   struct linux_statx_timestamp stx_atime;
   struct linux_statx_timestamp stx_btime;
   struct linux_statx_timestamp stx_ctime;
   struct linux_statx_timestamp stx_mtime;

   uint32_t stx_rdev_major;
   uint32_t stx_rdev_minor;

   uint32_t stx_dev_major;
   uint32_t stx_dev_minor;

   uint64_t unused[20];
};

#endif // #ifdef __linux__

// `mask` must contain exactly one "1" bit
static inline
int32_t index_of_property(uint32_t mask) {
  static const uint32_t de_bruijn_32 = 0x077CB531;
  static const uint8_t index32[] = {0,  1,  28, 2,  29, 14, 24, 3,  30, 22, 20,
                                    15, 25, 17, 4,  8,  31, 27, 13, 23, 21, 19,
                                    16, 7,  26, 12, 18, 6,  11, 5,  10, 9};
  return index32[(de_bruijn_32 * mask) >> 27];
}

// size of properties, in 64bit double words
static
int size_of_property[] = {
  1, // `STAT_FILE_KIND`
  1, // `STAT_FILE_SIZE`
  1, // `STAT_DEVICE_ID`, unconditional in `statx`
  1, // `STAT_FILE_ID`
  2, // `STAT_ACCESS_TIME`
  2, // `STAT_MODIFY_TIME`
  2, // `STAT_CHANGE_TIME`
  2  // `STAT_CREATE_TIME`
};

/* Briefly classify handles on windows based `GetFileType` and `getsockopt`.
   Difference between regular files/directories/reparse points is not handled by this function.
   These file types will all get represented as `Regular` here,
   and the caller should do further classification using file attributes.

   On error, `-1` is returned.
 */
#ifdef _WIN32
static inline
int32_t get_file_type_no_dir_check(HANDLE handle) {
  SetLastError(0);
  DWORD kind = GetFileType(handle);
  switch (kind) {
    case FILE_TYPE_DISK: return Regular;
    case FILE_TYPE_CHAR: {
      DWORD mode;
      return GetConsoleMode(handle, &mode) ? Console : CharDevice;
    }
    case FILE_TYPE_PIPE: {
      int opt = 0, opt_len = sizeof(int);
      if (0 == getsockopt((SOCKET)handle, SOL_SOCKET, SO_TYPE, (char*)&opt, &opt_len)) {
        return Socket;
      } else {
        return Pipe;
      }
    }
    case FILE_TYPE_UNKNOWN: {
      DWORD err = GetLastError();
      int opt = 0, opt_len = sizeof(int);
      if (0 == getsockopt((SOCKET)handle, SOL_SOCKET, SO_TYPE, (char*)&opt, &opt_len)) {
        return Socket;
      } else if (err) {
        SetLastError(err);
        return -1;
      } else {
        return UnknownFileKind;
      }
    }
    default:
      return UnknownFileKind;
  }
}
#endif

/* A generic `statx`/`getattrlist`-like function for retrieving information about OS objects.

   `file` determines which object to query:
   - if `file->kind == BY_HANDLE`, information about the fd `file->fd` is queried
   - if `file->kind == BY_PATH`, information about the path `file->path_spec.path` is queried:
     * if `file->path_spec.parent` is a valid fd/handle,
       `file->path_spec.path` will be interpreted relative to this handle.
       Not supported on Windows
     * if `file->path_spec.follow_symlink` is non-zero,
       and the last component of `file->path_spec.path` is a symlink,
       the target of the symlink will be queried.
       If `file->path_spec.follow_symlink` is zero, the symlink itself will be queried

   `request` is a bitmask obtained by OR-ing `STAT_*` constants.
   Only requested properties will be queried, to avoid redundant work.
   The requested properties will be written to `output_buf`, whose length is `buf_len`.
   The format of result written to `output_buf` is as follows:

   - the first 32bits is an unsigned integer containing the length of result, in bytes,
     including the length field itself

   - the next 32bits is an `uint32_t` obtained by OR-ing `STAT_*` constants
     of successfully returned properties.
     Some requested properties may be unsupported on certain file systems,
     in this case they will be missing from the returned bitmask.

     Note that an unsupported property will still occupy space in the output buffer,
     but the value at the position would be meaningless,
     so callers should always check the returned bitmask.
     As a consequence, the layout of the output buffer is fixed for any given input `request`.

   - the rest of the output buffer contain a list of values for each requested property.
     Each property is 8-byte aligned.
     The order of supported properties and the content of their value is as follows:

     - `STAT_FILE_KIND`: a `int64_t`, zero extended from `enum FileKind`,
       holding the kind of the file

     - `STAT_FILE_SIZE`: a `int64_t` holding the size of the file

     - `STAT_DEVICE_ID`: a `uint64_t` holding the ID of the device containing the file.
       Correspond to `st_dev` from `stat` on Unix-like systems,
       or the volume serial number on Windows

     - `STAT_FILE_ID`: the unique `uint64_t` id of the file in its file system.
       Correspond to `st_ino` from `stat` on Unix-like systems,
       or file id returned by `GetFileInformationByHandle` on Windows.

     - `STAT_ACCESS_TIME`/`STAT_MODIFY_TIME`/`STAT_CHANGE_TIME`/`STAT_CREATE_TIME`:
       two `int64_t` containing the last access/last data change/last metdata change/creation time
       of the target file.
       The first `int64_t` contain the second part, the second `int64_t` contain the nanosecond part

   This function is designed to be backward compatible in ABI.
   New properties can be appended in future versions of the runtime,
   while old code invoking this function with existing properties continue to work
   without the need for recompilation.
 */
static
int32_t moonbit_generic_stat(
  struct FileSpec *file, 
  uint32_t request,
  void *output_buf,
  int32_t buf_len
) {
  struct StatOutputBuffer *output = (struct StatOutputBuffer*)output_buf;

  if (buf_len < 8 || request & ~STAT_SUPPORTED_PROPERTY_MASK) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return -1;
  }

  output->returned_mask = 0;
  output->length = 8;
  for (uint32_t remaining_request = request; remaining_request;) {
    uint32_t next_request = remaining_request & (~remaining_request + 1);
    remaining_request ^= next_request;
    output->length += size_of_property[index_of_property(next_request)] << 3; 
  }

  if (output->length > buf_len) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return -1;
  }

#if defined(_WIN32)

#define MAKE_64(ty, hi, lo) (((ty)(hi) << 32) | (ty)(lo))

   static uint32_t by_handle_info_props =
     STAT_FILE_KIND
     | STAT_FILE_SIZE
     | STAT_DEVICE_ID
     | STAT_FILE_ID
     | STAT_ACCESS_TIME
     | STAT_MODIFY_TIME
     | STAT_CREATE_TIME
     | STAT_FILE_KIND;

   static uint32_t id_info_props = STAT_DEVICE_ID | STAT_FILE_ID;
   static uint32_t attr_info_props = STAT_FILE_KIND;
   static uint32_t basic_info_props =
     STAT_ACCESS_TIME
     | STAT_MODIFY_TIME
     | STAT_CHANGE_TIME
     | STAT_CREATE_TIME
     | STAT_FILE_KIND;

   struct {
     int32_t  file_type;
     DWORD    attributes;
     int64_t  file_size;
     uint64_t dev_id;
     uint64_t file_id;
     int64_t access_time;
     int64_t modify_time;
     int64_t change_time;
     int64_t create_time;
   } sys_stat;

   HANDLE handle;
   if (file->kind == BY_HANDLE) {
     handle = file->fd;
   } else {
     struct OpenOption options;
     options.access_mode = ReadAttributes;
     options.follow_symlink = file->path_spec.follow_symlink;
     options.is_async = 0;
     options.create_mode = 0;
     options.append = 0;
     options.sync_mode = 0;
     options.permission = 0;
     handle = moonbitlang_async_open_sync(file->path_spec.parent, file->path_spec.path, &options);
     if (handle == INVALID_HANDLE_VALUE)
       return -1;
   }

   int offset = 0;
   uint32_t remaining_request = request;

   if (request & STAT_FILE_KIND) {
     SetLastError(0);
     sys_stat.file_type = get_file_type_no_dir_check(handle);
     if (sys_stat.file_type < 0)
       goto exit;

     if (sys_stat.file_type != Regular) {
       // the remaining attributes are meaningless for non-disk handle
       remaining_request ^= STAT_FILE_KIND;
       goto write_result;
     }
   }

   if (!(remaining_request & ~attr_info_props)) {
     FILE_ATTRIBUTE_TAG_INFO info;
     if (GetFileInformationByHandleEx(handle, FileAttributeTagInfo, &info, sizeof(info))) {
       remaining_request &= ~attr_info_props;
       sys_stat.attributes = info.FileAttributes;
     }
   } else if ((remaining_request & STAT_CHANGE_TIME) || !(remaining_request & ~basic_info_props)) {
     FILE_BASIC_INFO info;
     if (GetFileInformationByHandleEx(handle, FileBasicInfo, &info, sizeof(info))) {
       remaining_request &= ~basic_info_props;
       sys_stat.attributes = info.FileAttributes;
       sys_stat.access_time = info.LastAccessTime.QuadPart;
       sys_stat.modify_time = info.LastWriteTime.QuadPart;
       sys_stat.change_time = info.ChangeTime.QuadPart;
       sys_stat.create_time = info.CreationTime.QuadPart;
     }
   }

    if (remaining_request == STAT_FILE_SIZE) {
      SetLastError(0);
      DWORD lo, hi;
      lo = GetFileSize(handle, &hi);
      if (!(lo == INVALID_FILE_SIZE && GetLastError())) {
        remaining_request ^= STAT_FILE_SIZE;
        sys_stat.file_size = MAKE_64(int64_t, hi, lo);
      }
    } else if (remaining_request) {
     BY_HANDLE_FILE_INFORMATION info;
     if (GetFileInformationByHandle(handle, &info)) {
       remaining_request &= ~by_handle_info_props;
       sys_stat.attributes = info.dwFileAttributes;
       sys_stat.file_size = MAKE_64(int64_t, info.nFileSizeHigh, info.nFileSizeLow);
       sys_stat.dev_id = info.dwVolumeSerialNumber;
       sys_stat.file_id = MAKE_64(uint64_t, info.nFileIndexHigh, info.nFileIndexLow);
       sys_stat.access_time = MAKE_64(
         int64_t,
         info.ftLastAccessTime.dwHighDateTime,
         info.ftLastAccessTime.dwLowDateTime
       );
       sys_stat.modify_time = MAKE_64(
         int64_t,
         info.ftLastWriteTime.dwHighDateTime,
         info.ftLastWriteTime.dwLowDateTime
       );
       sys_stat.create_time = MAKE_64(
         int64_t,
         info.ftCreationTime.dwHighDateTime,
         info.ftCreationTime.dwLowDateTime
       );
     }
   }

write_result:
  while (request) {
    uint32_t next_request = request & (~request + 1);
    request ^= next_request;

    int index = index_of_property(next_request);
    int size = size_of_property[index];

    // unsupported attribute
    if (next_request & remaining_request) {
      offset += size;
      continue;
    }

    output->returned_mask |= next_request;

    switch (next_request) {
      case STAT_FILE_KIND:
        if (sys_stat.file_type == Regular) {
          // further classify on-disk objects by attribute
          if (sys_stat.attributes & FILE_ATTRIBUTE_REPARSE_POINT)
            sys_stat.file_type = SymLink;
          else if (sys_stat.attributes & FILE_ATTRIBUTE_DIRECTORY)
            sys_stat.file_type = Directory;
        }
        output->properties[offset++] = sys_stat.file_type;
        break;

      case STAT_FILE_SIZE:
        output->properties[offset++] = sys_stat.file_size;
        break;

      case STAT_DEVICE_ID:
        output->properties[offset++] = sys_stat.dev_id;
        break;

      case STAT_FILE_ID:
        output->properties[offset++] = sys_stat.file_id;
        break;

      case STAT_ACCESS_TIME:
        output->properties[offset++] = sys_stat.access_time / 10000000;
        output->properties[offset++] = (sys_stat.access_time % 10000000) * 100;
        break;

      case STAT_MODIFY_TIME:
        output->properties[offset++] = sys_stat.modify_time / 10000000;
        output->properties[offset++] = (sys_stat.modify_time % 10000000) * 100;
        break;

      case STAT_CHANGE_TIME:
        output->properties[offset++] = sys_stat.change_time / 10000000;
        output->properties[offset++] = (sys_stat.change_time % 10000000) * 100;
        break;

      case STAT_CREATE_TIME:
        output->properties[offset++] = sys_stat.create_time / 10000000;
        output->properties[offset++] = (sys_stat.create_time % 10000000) * 100;
        break;
    }
  }

exit:
  if (file->kind == BY_PATH) {
    CloseHandle(handle);
  }
  if (output->returned_mask || file->kind == BY_PATH) {
    // For `BY_PATH` case, the input is already validated by `CreateFileW`,
    // so we treat empty return as all requested properties unsupported.
    return 0;
  }

  // For by-handle request, if nothing can be returned,
  // check if the handle is valid
  if (get_file_type_no_dir_check(handle) < 0)
    return -1;

  return 0;

#elif defined(__linux__)

  static unsigned int statx_masks[] = {
    STATX_TYPE,  // `STAT_FILE_KIND`
    STATX_SIZE,  // `STAT_FILE_SIZE`
    0,           // `STAT_DEVICE_ID`, unconditional in `statx`
    STATX_INO,   // `STAT_FILE_ID`
    STATX_ATIME, // `STAT_ACCESS_TIME`
    STATX_MTIME, // `STAT_MODIFY_TIME`
    STATX_CTIME, // `STAT_CHANGE_TIME`
    STATX_BTIME  // `STAT_CREATE_TIME`
  };

  int dirfd, flags = AT_STATX_SYNC_AS_STAT;
  const char *path;
  if (file->kind == BY_HANDLE) {
    dirfd = file->fd;
    path = "";
    flags |= AT_EMPTY_PATH;
  } else {
    path = file->path_spec.path;
    dirfd = file->path_spec.parent < 0 ? AT_FDCWD : file->path_spec.parent;
    if (!file->path_spec.follow_symlink)
      flags |= AT_SYMLINK_NOFOLLOW;
  }

  unsigned int statx_mask = 0;
  for (uint32_t remaining_request = request; remaining_request; ) {
    uint32_t next_request = remaining_request & (~remaining_request + 1);
    int index = index_of_property(next_request);
    statx_mask |= statx_masks[index];
    remaining_request ^= next_request;
  }

  struct linux_statx statx_info;
  if (syscall(SYS_statx, dirfd, path, flags, statx_mask, &statx_info) < 0)
    return -1;

  int offset = 0;
  while (request) {
    uint32_t next_request = request & (~request + 1);
    request ^= next_request;

    int index = index_of_property(next_request);
    unsigned int statx_mask = statx_masks[index];
    int size = size_of_property[index];

    if (statx_mask && 0 == (statx_info.stx_mask & statx_mask)) {
      // This property is not supported.
      // Still reserve space for it anyway to obtain a stable layout
      offset += size;
      continue;
    }

    output->returned_mask |= next_request;

    switch (next_request) {
      case STAT_FILE_KIND:
        switch (statx_info.stx_mode & S_IFMT) {
          case S_IFREG:
            output->properties[offset++] = Regular;
            break;
          case S_IFDIR:
            output->properties[offset++] = Directory;
            break;
          case S_IFLNK:
            output->properties[offset++] = SymLink;
            break;
          case S_IFSOCK:
            output->properties[offset++] = Socket;
            break;
          case S_IFIFO:
            output->properties[offset++] = Pipe;
            break;
          case S_IFBLK:
            output->properties[offset++] = BlockDevice;
            break;
          case S_IFCHR:
            output->properties[offset++] =
              file->kind == BY_HANDLE && isatty(file->fd)
              ? Console
              : CharDevice;
            break;
          default:
            output->properties[offset++] = UnknownFileKind;
            break;
        }
        break;

      case STAT_FILE_SIZE:
        output->properties[offset++] = statx_info.stx_size;
        break;

      case STAT_DEVICE_ID:
        output->properties[offset++] = makedev(statx_info.stx_dev_major, statx_info.stx_dev_minor);
        break;

      case STAT_FILE_ID:
        output->properties[offset++] = statx_info.stx_ino;
        break;

      case STAT_ACCESS_TIME:
        output->properties[offset++] = statx_info.stx_atime.tv_sec;
        output->properties[offset++] = statx_info.stx_atime.tv_nsec;
        break;
      case STAT_MODIFY_TIME:
        output->properties[offset++] = statx_info.stx_mtime.tv_sec;
        output->properties[offset++] = statx_info.stx_mtime.tv_nsec;
        break;
      case STAT_CHANGE_TIME:
        output->properties[offset++] = statx_info.stx_ctime.tv_sec;
        output->properties[offset++] = statx_info.stx_ctime.tv_nsec;
        break;
      case STAT_CREATE_TIME:
        output->properties[offset++] = statx_info.stx_btime.tv_sec;
        output->properties[offset++] = statx_info.stx_btime.tv_nsec;
        break;
    }
  }

  return 0;

#elif defined(__MACH__)

  // Supported request masks, ordered by `getattrlist`'s ordering in
  // https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/getattrlist.2.html
  static uint32_t properties_ordered[] = {
    STAT_DEVICE_ID,
    STAT_FILE_KIND,
    STAT_CREATE_TIME,
    STAT_MODIFY_TIME,
    STAT_CHANGE_TIME,
    STAT_ACCESS_TIME,
    STAT_FILE_ID,
    STAT_FILE_SIZE 
  };

  static const struct attrinfo {
    const uint32_t attr;
    const int32_t group_index; // index of the attribute group
    const uint32_t size;
  } attr_info[] = {
    { ATTR_CMN_OBJTYPE    , 0, sizeof(fsobj_type_t)    }, // STAT_FILE_KIND
    { ATTR_FILE_DATALENGTH, 3, sizeof(int64_t)         }, // STAT_FILE_SIZE
    { ATTR_CMN_DEVID      , 0, sizeof(dev_t)           }, // STAT_DEVICE_ID
    { ATTR_CMN_FILEID     , 0, sizeof(uint64_t)        }, // STAT_FILE_ID
    { ATTR_CMN_ACCTIME    , 0, sizeof(struct timespec) }, // STAT_ACCESS_TIME
    { ATTR_CMN_MODTIME    , 0, sizeof(struct timespec) }, // STAT_MODIFY_TIME
    { ATTR_CMN_CHGTIME    , 0, sizeof(struct timespec) }, // STAT_CHANGE_TIME
    { ATTR_CMN_CRTIME     , 0, sizeof(struct timespec) }, // STAT_CREATE_TIME
  };

  char attr_buf[
    sizeof(uint32_t) // length
    + sizeof(attribute_set_t) // `ATTR_CMN_RETURNED_ATTRS`
    + sizeof(fsobj_type_t) // `STAT_FILE_KIND`
    + sizeof(int64_t) // `STAT_FILE_SIZE`
    + sizeof(dev_t) // `STAT_DEVICE_ID`
    + sizeof(uint64_t) // `STAT_FILE_ID`
    + sizeof(struct timespec) * 4 // `STAT_{ACCESS,MODIFY,CHANGE,CREATE},_TIME`
  ];

  int offset_of_property[sizeof(attr_info) / sizeof(attr_info[0])];

  struct attrlist attr_list;
  memset(&attr_list, 0, sizeof(attr_list));
  attr_list.bitmapcount = ATTR_BIT_MAP_COUNT;
  attr_list.commonattr = ATTR_CMN_RETURNED_ATTRS;

  for (
    int i = 0, offset = sizeof(uint32_t) + sizeof(attribute_set_t);
    i < sizeof(attr_info) / sizeof(attr_info[0]);
    ++i
  ) {
    uint32_t const property = properties_ordered[i];
    uint32_t const index = index_of_property(property);
    struct attrinfo const *info = attr_info + index;
    if (0 == (request & property))
      continue;

    (&attr_list.commonattr)[info->group_index] |= info->attr;
    offset_of_property[index] = offset;
    offset += info->size;
  }

  int ret;
  unsigned long options = FSOPT_PACK_INVAL_ATTRS;
  if (file->kind == BY_HANDLE) {
    ret = fgetattrlist(file->fd, &attr_list, attr_buf, sizeof(attr_buf), options);
  } else {
    if (!file->path_spec.follow_symlink)
      options |= FSOPT_NOFOLLOW;

    if (file->path_spec.parent < 0) {
      ret = getattrlist(file->path_spec.path, &attr_list, attr_buf, sizeof(attr_buf), options);
    } else {
      ret = getattrlistat(
        file->path_spec.parent,
        file->path_spec.path,
        &attr_list,
        attr_buf,
        sizeof(attr_buf),
        options
      );
    }
  }

  if (ret < 0) {
    if (errno == EINVAL && file->kind == BY_HANDLE) {
      // `getattrlist` only support vnode objects, for other things such as pipe and socket,
      // fallback to `fstat`.
      struct stat stat_obj;
      if (fstat(file->fd, &stat_obj) < 0)
        return -1; 

      if (!(request & STAT_FILE_KIND))
        return 0;

      output->returned_mask = STAT_FILE_KIND;
      switch (stat_obj.st_mode & S_IFMT) {
        case S_IFREG:
          output->properties[0] = Regular;
          break;
        case S_IFDIR:
          output->properties[0] = Directory;
          break;
        case S_IFLNK:
          output->properties[0] = SymLink;
          break;
        case S_IFSOCK:
          output->properties[0] = Socket;
          break;
        case S_IFIFO:
          output->properties[0] = Pipe;
          break;
        case S_IFBLK:
          output->properties[0] = BlockDevice;
          break;
        case S_IFCHR:
          output->properties[0] =
            file->kind == BY_HANDLE && isatty(file->fd)
            ? Console
            : CharDevice;
          break;
        default:
          output->properties[0] = UnknownFileKind;
          break;
      }
      return 0;
    } else {
      return -1;
    }
  }

  uint32_t attr_buf_len = *(uint32_t*)attr_buf;
  attrgroup_t *returned_attrs = (attrgroup_t*)(attr_buf + 4);

  int offset = 0;
  while (request) {
    uint32_t next_request = request & (~request + 1);
    request ^= next_request;

    int index = index_of_property(next_request);
    struct attrinfo const *info = attr_info + index;
    int size = size_of_property[index];
    int attr_offset = offset_of_property[index];

    if (0 == (info->attr & returned_attrs[info->group_index])) {
      // This property is not supported.
      // Still reserve space for it anyway to obtain a stable layout
      offset += size;
      continue;
    }

    if (attr_offset + info->size > attr_buf_len)
      continue;

    output->returned_mask |= next_request;
    char *attr = attr_buf + attr_offset;

    switch (next_request) {
      case STAT_FILE_KIND:
        switch (*(fsobj_type_t*)attr) {
          case VREG:
            output->properties[offset++] = Regular;
            break;
          case VDIR:
            output->properties[offset++] = Directory;
            break;
          case VLNK:
            output->properties[offset++] = SymLink;
            break;
          case VSOCK:
            output->properties[offset++] = Socket;
            break;
          case VFIFO:
            output->properties[offset++] = Pipe;
            break;
          case VBLK:
            output->properties[offset++] = BlockDevice;
            break;
          case VCHR:
            output->properties[offset++] = CharDevice;
            break;
          default:
            output->properties[offset++] = UnknownFileKind;
            break;
        }
        break;

      case STAT_FILE_SIZE:
        output->properties[offset++] = *(int64_t*)attr;
        break;

      case STAT_DEVICE_ID:
        output->properties[offset++] = *(dev_t*)attr;
        break;

      case STAT_FILE_ID:
        output->properties[offset++] = *(uint64_t*)attr;
        break;

      case STAT_ACCESS_TIME:
      case STAT_MODIFY_TIME:
      case STAT_CHANGE_TIME:
      case STAT_CREATE_TIME:
        output->properties[offset++] = ((struct timespec*)attr)->tv_sec;
        output->properties[offset++] = ((struct timespec*)attr)->tv_nsec;
        break;
    }
  }

  return 0;

#else
  errno = ENOSYS;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_fstatx_sync(HANDLE fd, uint32_t request, void *buf, int32_t buf_len) {
  struct FileSpec file;
  file.kind = BY_HANDLE;
  file.fd = fd;
  return moonbit_generic_stat(&file, request, buf, buf_len);
}

static
int32_t moonbitlang_async_statx_sync(
  os_string_t path,
  uint32_t request,
  void *buf,
  int32_t buf_len,
  HANDLE parent,
  int32_t follow_symlink
) {
  struct FileSpec file;
  file.kind = BY_PATH;
  file.path_spec.path = path;
  file.path_spec.parent = parent;
  file.path_spec.follow_symlink = follow_symlink;
  return moonbit_generic_stat(&file, request, buf, buf_len);
}

// ===== openat job =====

struct openat_job {
  HANDLE parent;
  os_string_t filename;
  struct OpenOption options;
  HANDLE result;

  uint32_t stat_request;
  void *stat_buf;
  int32_t stat_buf_len;
};

static
void free_openat_job(struct openat_job *job) {
  moonbit_decref(job->filename);
  moonbit_decref(job->stat_buf);
}

static
int32_t openat_job_worker(struct openat_job *job, int32_t *err_out) {
  job->result = moonbitlang_async_open_sync(
    job->parent,
    job->filename,
    &job->options
  );

  // Retrieve basic stat about the newly opened file in the same job
  // to save some thread pool communication cost
#ifdef _WIN32

  if (job->result == INVALID_HANDLE_VALUE) {
    *err_out = GetLastError();
    return -1;
  }

#else

  if (job->result < 0) {
    *err_out = errno;
    return -1;
  }

#endif

  int ret = moonbitlang_async_fstatx_sync(
    job->result,
    job->stat_request,
    job->stat_buf,
    job->stat_buf_len
  );
  if (ret < 0) {
    *err_out = GetLastError();
#ifdef _WIN32
    CloseHandle(job->result);
#else
    close(job->result);
#endif
    return -1;
  }
  return 0;
}


MOONBIT_FFI_EXPORT
struct openat_job *moonbitlang_async_make_openat_job(
  HANDLE parent,
  os_string_t filename,
  int access_mode,
  int create_mode,
  int append,
  int sync_mode,
  int permission,
  uint32_t stat_request,
  void *stat_buf,
  int32_t stat_buf_len
) {
  struct openat_job *job = MAKE_JOB(openat, 0);
  job->parent = parent;
  job->filename = filename;
  job->options.access_mode = access_mode;
  job->options.is_async = access_mode == ListDirectory; // for `ReadDirectoryChangesW`
  job->options.follow_symlink = 1; // TODO: expose this to end users
  job->options.create_mode = create_mode;
  job->options.append = append;
  job->options.sync_mode = sync_mode;
  job->options.permission = permission;
  job->stat_buf = stat_buf;
  job->stat_buf_len = stat_buf_len;
  job->stat_request = stat_request;
  return job;
}

MOONBIT_FFI_EXPORT
HANDLE moonbitlang_async_openat_job_get_fd(struct openat_job *job) {
  return job->result;
}

// Keep the old open job entry points for runtime compatibility.
MOONBIT_FFI_EXPORT
struct openat_job *moonbitlang_async_make_open_job(
  os_string_t filename,
  int access_mode,
  int create_mode,
  int append,
  int sync_mode,
  int permission,
  uint32_t stat_request,
  void *stat_buf,
  int32_t stat_buf_len
) {
#ifdef _WIN32
  HANDLE parent = INVALID_HANDLE_VALUE;
#else
  HANDLE parent = -1;
#endif
  return moonbitlang_async_make_openat_job(
    parent,
    filename,
    access_mode,
    create_mode,
    append,
    sync_mode,
    permission,
    stat_request,
    stat_buf,
    stat_buf_len
  );
}

MOONBIT_FFI_EXPORT
HANDLE moonbitlang_async_open_job_get_fd(struct openat_job *job) {
  return moonbitlang_async_openat_job_get_fd(job);
}

// ===== fstatx job, get properties of an existing fd =====
struct fstatx_job {
  HANDLE fd;
  uint32_t request;
  void *buf;
  int32_t buf_len;
};

static
void free_fstatx_job(struct fstatx_job *job) {
  moonbit_decref(job->buf);
}

static
int32_t fstatx_job_worker(struct fstatx_job *job, int32_t *err_out) {
  if (moonbitlang_async_fstatx_sync(job->fd, job->request, job->buf, job->buf_len) < 0) {
    *err_out = GetLastError();
    return -1;
  }
  return 0;
}

MOONBIT_FFI_EXPORT
struct fstatx_job *moonbitlang_async_make_fstatx_job(
  HANDLE fd,
  uint32_t request,
  void *buf,
  int32_t buf_len
) {
  struct fstatx_job *job = MAKE_JOB(fstatx, 0);
  job->fd = fd;
  job->request = request;
  job->buf = buf;
  job->buf_len = buf_len;
  return job;
}

// ===== statx job, get properties of a path=====
struct statx_job {
  os_string_t path;
  uint32_t request;
  void *buf;
  int32_t buf_len;
  HANDLE parent;
  int32_t follow_symlink;
};

static
void free_statx_job(struct statx_job *job) {
  moonbit_decref(job->path);
  moonbit_decref(job->buf);
}

static
int32_t statx_job_worker(struct statx_job *job, int32_t *err_out) {
  int32_t ret = moonbitlang_async_statx_sync(
    job->path,
    job->request,
    job->buf,
    job->buf_len,
    job->parent,
    job->follow_symlink
  );
  if (ret < 0)
    *err_out = GetLastError();

  return ret;
}

MOONBIT_FFI_EXPORT
struct statx_job *moonbitlang_async_make_statx_job(
  os_string_t path,
  uint32_t request,
  void *buf,
  int32_t buf_len,
  HANDLE parent,
  int32_t follow_symlink
) {
  struct statx_job *job = MAKE_JOB(statx, 0);
  job->path = path;
  job->request = request;
  job->buf = buf;
  job->buf_len = buf_len;
  job->parent = parent;
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
  void *worker = moonbitlang_async_get_current_worker();

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

  if (moonbitlang_async_enter_cancellable_region(worker)) {
    SetLastError(ERROR_OPERATION_ABORTED);
    return -1;
  }

  BOOL ret = LockFileEx(
    fd,
    exclusive ? LOCKFILE_EXCLUSIVE_LOCK : 0,
    0, // reserved
    1,
    0,
    &overlapped
  );
  moonbitlang_async_leave_cancellable_region(worker);

  return ret ? 0 : -1;

#else

  if (moonbitlang_async_enter_cancellable_region(worker)) {
    errno = EINTR;
    return -1;
  }

  int ret = flock(fd, exclusive ? LOCK_EX : LOCK_SH);
  moonbitlang_async_leave_cancellable_region(worker);

  return ret;

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

// ===== removeat job, remove file from file system relative to a directory =====
static
int32_t moonbitlang_async_removeat_sync(HANDLE parent, os_string_t path) {
#ifdef _WIN32

  struct OpenOption options;
  options.access_mode = DeleteAccess;
  options.follow_symlink = 0;
  options.is_async = 0;
  options.create_mode = 0;
  options.append = 0;
  options.sync_mode = 0;
  options.permission = 0;

  HANDLE handle = moonbitlang_async_open_sync(parent, path, &options);
  if (handle == INVALID_HANDLE_VALUE)
    return -1;

#if _WIN32_WINNT >= 0x0A00
  FILE_DISPOSITION_INFO_EX info;
  info.Flags =
    FILE_DISPOSITION_FLAG_DELETE | FILE_DISPOSITION_FLAG_POSIX_SEMANTICS;
  BOOL ret = SetFileInformationByHandle(
    handle,
    FileDispositionInfoEx,
    &info,
    sizeof(info)
  );
#else
  FILE_DISPOSITION_INFO info;
  info.DeleteFile = TRUE;
  BOOL ret = SetFileInformationByHandle(
    handle,
    FileDispositionInfo,
    &info,
    sizeof(info)
  );
#endif
  DWORD err = ret ? ERROR_SUCCESS : GetLastError();
  CloseHandle(handle);

  if (!ret)
    SetLastError(err);

  return ret ? 0 : -1;

#elif defined(__MACH__)

  int dirfd = parent < 0 ? AT_FDCWD : parent;
  int ret = unlinkat(dirfd, path, 0);
  // Darwin reports EPERM rather than EISDIR when unlinking a directory.
  if (ret < 0 && errno == EPERM) {
    int err = errno;
    ret = unlinkat(dirfd, path, AT_REMOVEDIR);
    if (ret < 0 && errno == ENOTDIR)
      errno = err;
  }
  return ret;

#elif defined(__linux__)

  int dirfd = parent < 0 ? AT_FDCWD : parent;
  int ret = unlinkat(dirfd, path, 0);
  if (ret < 0 && errno == EISDIR)
    ret = unlinkat(dirfd, path, AT_REMOVEDIR);
  return ret;

#else

  return remove(path);

#endif
}

struct removeat_job {
  HANDLE parent;
  os_string_t path;
};

static
void free_removeat_job(struct removeat_job *job) {
  moonbit_decref(job->path);
}

static
int32_t removeat_job_worker(struct removeat_job *job, int32_t *err_out) {
  if (moonbitlang_async_removeat_sync(job->parent, job->path) < 0) {
    *err_out = GetLastError();
    return -1;
  }
  return 0;
}

struct removeat_job *moonbitlang_async_make_removeat_job(
  HANDLE parent,
  os_string_t path
) {
  struct removeat_job *job = MAKE_JOB(removeat, 0);
  job->parent = parent;
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
    FILE_ATTRIBUTE_NORMAL | FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
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

  PWSTR resolved_target = NULL;

  // A plain relative symlink target is resolved relative to the directory
  // containing the link, not relative to the process's current directory.
  // Root-relative and drive-relative paths have separate DOS path semantics and
  // are intentionally left to Windows.
  BOOL target_is_relative =
    target_len > 0
    && target[0] != L'\\'
    && target[0] != L'/'
    && !(target_len >= 2 && target[1] == L':');

  if (target_is_relative) {
#if _WIN32_WINNT >= 0x0602
    PWSTR link_directory = NULL;
    HRESULT hr = PathAllocCombine(
      path,
      L"..",
      PATHCCH_ALLOW_LONG_PATHS,
      &link_directory
    );
    if (FAILED(hr)) {
      SetLastError(HRESULT_CODE(hr));
      return -1;
    }

    hr = PathAllocCombine(
      link_directory,
      target,
      PATHCCH_ALLOW_LONG_PATHS,
      &resolved_target
    );
    LocalFree(link_directory);
    if (FAILED(hr)) {
      SetLastError(HRESULT_CODE(hr));
      return -1;
    }
#else
    SetLastError(ERROR_NOT_SUPPORTED);
    return -1;
#endif
  }

  DWORD attrs = GetFileAttributesW(resolved_target ? resolved_target : target);
  if (resolved_target)
    LocalFree(resolved_target);

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
#elif defined(__MACH__)
  if (job->result) {
    malloc_zone_t *zone = malloc_zone_from_ptr(job->result);
    malloc_zone_free(zone, job->result);
  }
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

#ifdef _WIN32
// Win32 path resolution trims trailing dots and spaces from each component
// and maps reserved device names (CON, PRN, etc.) to devices,
// The `\\?` prefix prevent these special resolution rules.
// So if the returned path may hit any of the above rules,
// we must not trim the `\\?\` prefix or the meaning of the path changes.
static
int dos_path_is_exact(WCHAR *path, size_t len) {
  if (len >= MAX_PATH)
    return 0;

  size_t start = 0;
  while (start < len) {
    size_t end = start;
    while (end < len && path[end] != L'\\')
      end++;

    if (end == start)
      return 0;

    if (path[end - 1] == L'.' || path[end - 1] == L' ')
      return 0;

    // temporarily turn the delimiter into nul for `RtlIsDosDeviceName_U`
    if (end < len)
      path[end] = 0;

    BOOL is_dos_device = RtlIsDosDeviceName_U(path + start);

    if (end < len)
      path[end] = L'\\';

    if (is_dos_device)
      return 0;

    start = end + 1;
  }
  return 1;
}
#endif

char *moonbitlang_async_get_realpath_result(struct realpath_job *job) {
#ifdef _WIN32
  size_t len = wcslen(job->result);
  if (wcsncmp(job->result, L"\\\\?\\UNC\\", 8) == 0) {
    if (dos_path_is_exact(job->result + 8, len - 8)) {
      job->result[6] = L'\\';
      return (char*)job->result + 6 * sizeof(WCHAR);
    }
    return (char*)job->result;
  } else if (wcsncmp(job->result, L"\\\\?\\", 4) == 0) {
    if (dos_path_is_exact(job->result + 4, len - 4))
      return (char*)job->result + 4 * sizeof(WCHAR);
    return (char*)job->result;
  } else {
    return (char*)job->result;
  }
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
