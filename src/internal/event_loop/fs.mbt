// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
#valtype
pub(all) struct FileIdentity {
  dev_id : UInt64
  file_id : UInt64
} derive(Eq, Hash)

///|
pub async fn open(
  path : StringView,
  // 0 => read only, 1 => write only, 2 => read write, 3 => directory listing
  access : Int,
  // See `@fs.CreateMode` for more details
  create~ : Int,
  append~ : Bool,
  // 0 => no sync, 1 => data sync, 2 => full sync
  sync~ : Int,
  // permission for file when new file is created
  mode~ : Int,
  context~ : String,
) -> (IoHandle, FileIdentity) {
  let path_bytes = @os_string.encode(path)
  let stat_buf = FixedArray::make(32, b'\x00')
  let job = Job::open(
    path_bytes,
    access,
    create~,
    append~,
    sync~,
    mode~,
    stat_request=STAT_FILE_KIND | STAT_DEVICE_ID | STAT_FILE_ID,
    stat_buf~,
    stat_buf_len=stat_buf.length(),
  )
  defer job.0.free()
  try perform_job_in_worker(job.0, context~, cancellable=true) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  } noraise {
    _ => {
      let fd = job.fd()
      guard! stat_buf
        is [u32le(_), u32le(mask), i64le(kind), u64le(dev_id), u64le(file_id)]
      guard (mask & STAT_FILE_KIND) > 0 else {
        // we need at least the file kind
        raise @os_error.OSError(
          @os_error.errno_ENOTDIR,
          context="\{context}: \{path.escape()}",
        )
      }
      let kind = @fd_util.FileKind::unsafe_from_int(kind.to_int())
      let io = IoHandle::from_fd(
        fd,
        kind~,
        is_async=access is 3 || (!(platform is Windows) && kind.can_poll()),
        read_only=access is 0,
      )
      if append {
        // For append mode file descriptor, let the OS do the work.
        // Reading is unaffected by `append`.
        io.write_offset = -1
      }
      (io, { dev_id, file_id })
    }
  }
}

///|
pub async fn fstatx(
  fd : @fd_util.Fd,
  request : UInt,
  buf : FixedArray[Byte],
  buf_len : Int,
  context~ : String,
) -> Unit {
  let job = Job::fstatx(fd, request, buf, buf_len)
  defer job.free()
  ignore <| perform_job_in_worker(job, context~)
}

///|
async fn fstatx_single(
  fd : @fd_util.Fd,
  request : UInt,
  length : Int,
  context~ : String,
) -> ArrayView[Byte] {
  let buf = FixedArray::make(8 + (length << 3), b'\x00')
  fstatx(fd, request, buf, buf.length(), context~)
  guard! buf is [u32le(_), u32le(mask), .. payload]
  guard (mask & request) != 0 else {
    raise @os_error.OSError(@os_error.errno_ENOTSUP, context~)
  }
  payload
}

///|
pub async fn statx(
  path : StringView,
  parent~ : @fd_util.Fd,
  follow_symlink~ : Bool,
  request : UInt,
  buf : FixedArray[Byte],
  buf_len : Int,
  context~ : String,
) -> Unit {
  let path_bytes = @os_string.encode(path)
  let job = Job::statx(
    path_bytes,
    parent~,
    follow_symlink~,
    request,
    buf,
    buf_len,
  )
  defer job.free()
  try perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  } noraise {
    _ => ()
  }
}

///|
async fn statx_single(
  path : StringView,
  parent~ : @fd_util.Fd,
  follow_symlink~ : Bool,
  request : UInt,
  length : Int,
  context~ : String,
) -> ArrayView[Byte] {
  let buf = FixedArray::make(8 + (length << 3), b'\x00')
  statx(path, parent~, follow_symlink~, request, buf, buf.length(), context~)
  guard! buf is [u32le(_), u32le(mask), .. payload]
  guard (mask & request) != 0 else {
    raise @os_error.OSError(@os_error.errno_ENOTSUP, context~)
  }
  payload
}

///|
pub async fn kind_of_fd(
  fd : @fd_util.Fd,
  context~ : String,
) -> @fd_util.FileKind {
  guard! fstatx_single(fd, STAT_FILE_KIND, 1, context~) is [u64le(kind)]
  @fd_util.FileKind::unsafe_from_int(kind.to_int())
}

///|
/// If `parent` is a valid fd and `path` is relative,
/// `path` will be interpreted relative to the directory pointed by `parent`,
/// see `fstatat` for more details.
/// `parent` is not supported on Windows.
pub async fn file_kind_by_path(
  path : StringView,
  parent~ : @fd_util.Fd,
  follow_symlink~ : Bool,
  context~ : String,
) -> @fd_util.FileKind {
  guard! statx_single(
      path,
      parent~,
      follow_symlink~,
      STAT_FILE_KIND,
      1,
      context~,
    )
    is [u64le(kind)]
  @fd_util.FileKind::unsafe_from_int(kind.to_int())
}

///|
pub async fn file_size(fd : @fd_util.Fd, context~ : String) -> Int64 {
  guard! fstatx_single(fd, STAT_FILE_SIZE, 1, context~) is [i64le(size)]
  size
}

///|
pub async fn mtime(fd : @fd_util.Fd, context~ : String) -> (Int64, Int) {
  guard! fstatx_single(fd, STAT_MODIFY_TIME, 2, context~)
    is [i64le(sec), i64le(nsec)]
  (sec, nsec.to_int())
}

///|
pub async fn atime(fd : @fd_util.Fd, context~ : String) -> (Int64, Int) {
  guard! fstatx_single(fd, STAT_ACCESS_TIME, 2, context~)
    is [i64le(sec), i64le(nsec)]
  (sec, nsec.to_int())
}

///|
pub async fn ctime(fd : @fd_util.Fd, context~ : String) -> (Int64, Int) {
  guard! fstatx_single(fd, STAT_CHANGE_TIME, 2, context~)
    is [i64le(sec), i64le(nsec)]
  (sec, nsec.to_int())
}

///|
pub async fn mtime_by_path(
  path : StringView,
  follow_symlink~ : Bool,
  context~ : String,
) -> (Int64, Int) {
  guard! statx_single(
      path,
      parent=@fd_util.invalid_fd,
      follow_symlink~,
      STAT_MODIFY_TIME,
      2,
      context~,
    )
    is [i64le(sec), i64le(nsec)]
  (sec, nsec.to_int())
}

///|
pub async fn atime_by_path(
  path : StringView,
  follow_symlink~ : Bool,
  context~ : String,
) -> (Int64, Int) {
  guard! statx_single(
      path,
      parent=@fd_util.invalid_fd,
      follow_symlink~,
      STAT_ACCESS_TIME,
      2,
      context~,
    )
    is [i64le(sec), i64le(nsec)]
  (sec, nsec.to_int())
}

///|
pub async fn ctime_by_path(
  path : StringView,
  follow_symlink~ : Bool,
  context~ : String,
) -> (Int64, Int) {
  guard! statx_single(
      path,
      parent=@fd_util.invalid_fd,
      follow_symlink~,
      STAT_CHANGE_TIME,
      2,
      context~,
    )
    is [i64le(sec), i64le(nsec)]
  (sec, nsec.to_int())
}

///|
pub async fn access(path : StringView, acc : Access, context~ : String) -> Int {
  let path_bytes = @os_string.encode(path)
  let job = Job::access(path_bytes, acc)
  defer job.free()
  perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  }
}

///|
pub async fn chmod(path : StringView, mode : Int, context~ : String) -> Unit {
  let path_bytes = @os_string.encode(path)
  let job = Job::chmod(path_bytes, mode)
  defer job.free()
  try perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  } noraise {
    _ => ()
  }
}

///|
pub async fn IoHandle::fsync(
  handle : IoHandle,
  only_data~ : Bool,
  context~ : String,
) -> Unit {
  let job = Job::fsync(handle.fd, only_data)
  defer job.free()
  perform_job_in_worker(job, context~) |> ignore
}

///|
pub async fn IoHandle::lock(
  handle : IoHandle,
  exclusive~ : Bool,
  context~ : String,
) -> Unit {
  let job = Job::flock(handle.fd, exclusive)
  defer job.free()
  perform_job_in_worker(job, cancellable=true, context~) |> ignore
}

///|
pub async fn remove(path : StringView, context~ : String) -> Unit {
  let path_bytes = @os_string.encode(path)
  let job = Job::remove(path_bytes)
  defer job.free()
  try perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  } noraise {
    _ => ()
  }
}

///|
pub async fn rename(
  old_path : StringView,
  new_path : StringView,
  replace~ : Bool,
  context~ : String,
) -> Unit {
  let old_path_bytes = @os_string.encode(old_path)
  let new_path_bytes = @os_string.encode(new_path)
  let job = Job::rename(old_path_bytes, new_path_bytes, replace~)
  defer job.free()
  try perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(
        errno,
        context="\{context}: \{old_path.escape()} => \{new_path.escape()}",
      )
    err => raise err
  } noraise {
    _ => ()
  }
}

///|
pub async fn symlink(
  target : StringView,
  path : StringView,
  force_symlink~ : Bool,
  context~ : String,
) -> Unit {
  let target_bytes = @os_string.encode(target)
  let path_bytes = @os_string.encode(path)
  let job = Job::symlink(target_bytes, path_bytes, force_symlink~)
  defer job.free()
  try perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(
        errno,
        context="\{context}: \{target.escape()} => \{path.escape()}",
      )
    err => raise err
  } noraise {
    _ => ()
  }
}

///|
pub async fn mkdir(path : StringView, mode~ : Int, context~ : String) -> Unit {
  let path_bytes = @os_string.encode(path)
  let job = Job::mkdir(path_bytes, mode)
  defer job.free()
  try perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  } noraise {
    _ => ()
  }
}

///|
pub async fn rmdir(path : StringView, context~ : String) -> Unit {
  let path_bytes = @os_string.encode(path)
  let job = Job::rmdir(path_bytes)
  defer job.free()
  try perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  } noraise {
    _ => ()
  }
}

///|
pub async fn IoHandle::readdir(
  dir : IoHandle,
  buf : @c_buffer.Buffer,
  len : Int,
  restart~ : Bool,
  context~ : String,
) -> Int {
  guard! dir.read is Idle
  dir.read = Submitted
  defer {
    dir.read = Idle
  }
  let job = Job::readdir(dir.fd, buf, len, restart)
  defer job.free()
  perform_job_in_worker(job, context~)
}

///|
#cfg(any(target="native", target="wasm"))
pub async fn realpath(path : StringView, context~ : String) -> String {
  let path_bytes = @os_string.encode(path)
  let job = Job::realpath(path_bytes)
  defer job.free()
  let _ = perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  }
  let c_path = job.get_realpath_result()
  @os_string.decode(c_path)
}

///|
#cfg(all(target="native", not(platform="windows")))
pub async fn inotify_add_watch(
  inotify : @fd_util.Fd,
  path : StringView,
  is_dir~ : Bool,
  context~ : String,
) -> @fd_util.Fd {
  let path_bytes = @os_string.encode(path)
  let job = Job::inotify_add_watch(inotify, path_bytes, is_dir)
  defer job.free()
  perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  }
}

///|
#cfg(platform="windows")
extern "C" fn read_dir_changes_ffi(fd : @fd_util.Fd, result : IoResult) -> Int = "moonbitlang_async_read_dir_changes"

///|
/// zero return value indicates overflow
#cfg(platform="windows")
pub async fn IoHandle::read_dir_changes(
  handle : IoHandle,
  buf : @c_buffer.Buffer,
  len : Int,
  context~ : String,
) -> Int {
  @coroutine.check_cancellation()
  guard! handle.kind is Directory
  let result = IoResult::for_read_dir_changes(buf, len~)
  defer result.free()
  let n = read_dir_changes_ffi(handle.fd, result)
  if n >= 0 {
    // The `pause` here prevent a busy loop from exhausting the whole program,
    // and give chance for other tasks to execute.
    @coroutine.protect_from_cancel(@coroutine.pause)
    n
  } else if @os_error.is_nonblocking_io_error() {
    handle.wait_read_result(result, context~)
    result.status(handle.fd, context~) catch {
      @os_error.OSError(_) as err if err.is_ERROR_NOTIFY_ENUM_DIR() => 0
      err => raise err
    }
  } else {
    @os_error.check_errno(context)
    panic()
  }
}
