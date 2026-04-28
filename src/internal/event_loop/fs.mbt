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
pub async fn open_detached(
  path : StringView,
  // 0 => read only, 1 => write only, 2 => read write
  access : Int,
  // See `@fs.CreateMode` for more details
  create~ : Int,
  append~ : Bool,
  // 0 => no sync, 1 => data sync, 2 => full sync
  sync~ : Int,
  // permission for file when new file is created
  mode~ : Int,
  context~ : String,
) -> OpenResult {
  let path_bytes = @os_string.encode(path)
  let result = Job::open(path_bytes, access, create~, append~, sync~, mode~)
  fn cancel(job_id) raise {
    guard curr_loop.val is Some(evloop)
    evloop.cancel_job_in_worker(job_id, context~)
  }

  try perform_job_in_worker(result.0, context~, cancel~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  } noraise {
    _ => result
  }
}

///|
pub async fn open(
  path : StringView,
  // 0 => read only, 1 => write only, 2 => read write
  access : Int,
  // See `@fs.CreateMode` for more details
  create~ : Int,
  append~ : Bool,
  // 0 => no sync, 1 => data sync, 2 => full sync
  sync~ : Int,
  // permission for file when new file is created
  mode~ : Int,
  context~ : String,
) -> IoHandle {
  let result = open_detached(
    path,
    access,
    create~,
    append~,
    sync~,
    mode~,
    context~,
  )
  let fd = result.fd()
  let kind = result.kind()
  // On Windows, due to a lot of complexity,
  // we use synchronous IO + thread pool unconditionally for regular files.
  // However, on Windows, overlapped IO must be enabled on file creation time,
  // but we cannot know the kind of a file before opening it.
  // So, we use synchronous IO unconditionally for everything opened by path,
  // including named pipes.
  IoHandle::from_fd(fd, kind~, is_async=!IS_WINDOWS && kind.can_poll())
}

///|
pub async fn kind_of_fd(
  fd : @fd_util.Fd,
  context~ : String,
) -> @fd_util.FileKind {
  perform_job_in_worker(Job::kind_of_fd(fd), context~)
  |> @fd_util.FileKind::unsafe_from_int
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
  let path_bytes = @os_string.encode(path)
  let job = Job::file_kind_by_path(parent, path_bytes, follow_symlink~)
  try perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  } noraise {
    result => @fd_util.FileKind::unsafe_from_int(result)
  }
}

///|
pub async fn file_size(fd : @fd_util.Fd, context~ : String) -> Int64 {
  let job = Job::file_size(fd)
  let _ = perform_job_in_worker(job, context~)
  job.get_file_size_result()
}

///|
pub async fn file_time(
  fd : @fd_util.Fd,
  context~ : String,
) -> @fd_util.FileTime {
  let result = @fd_util.FileTime::new()
  let job = Job::file_time(fd, result)
  let _ = perform_job_in_worker(job, context~)
  result
}

///|
pub async fn file_time_by_path(
  path : StringView,
  follow_symlink~ : Bool,
  context~ : String,
) -> @fd_util.FileTime {
  let path_bytes = @os_string.encode(path)
  let result = @fd_util.FileTime::new()
  let job = Job::file_time_by_path(path_bytes, result, follow_symlink~)
  try perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  } noraise {
    _ => ()
  }
  result
}

///|
pub async fn access(path : StringView, acc : Access, context~ : String) -> Int {
  let path_bytes = @os_string.encode(path)
  perform_job_in_worker(Job::access(path_bytes, acc), context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  }
}

///|
pub async fn chmod(path : StringView, mode : Int, context~ : String) -> Unit {
  let path_bytes = @os_string.encode(path)
  try perform_job_in_worker(Job::chmod(path_bytes, mode), context~) catch {
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
  perform_job_in_worker(Job::fsync(handle.fd, only_data), context~) |> ignore
}

///|
pub async fn IoHandle::lock(
  handle : IoHandle,
  exclusive~ : Bool,
  context~ : String,
) -> Unit {
  guard curr_loop.val is Some(evloop)
  perform_job_in_worker(
    Job::flock(handle.fd, exclusive),
    cancel=job_id => evloop.cancel_job_in_worker(job_id, context~),
    context~,
  )
  |> ignore
}

///|
pub async fn remove(path : StringView, context~ : String) -> Unit {
  let path_bytes = @os_string.encode(path)
  try perform_job_in_worker(Job::remove(path_bytes), context~) catch {
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
  try
    perform_job_in_worker(
      Job::rename(old_path_bytes, new_path_bytes, replace~),
      context~,
    )
  catch {
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
  context~ : String,
) -> Unit {
  let target_bytes = @os_string.encode(target)
  let path_bytes = @os_string.encode(path)
  try
    perform_job_in_worker(Job::symlink(target_bytes, path_bytes), context~)
  catch {
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
  try perform_job_in_worker(Job::mkdir(path_bytes, mode), context~) catch {
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
  try perform_job_in_worker(Job::rmdir(path_bytes), context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  } noraise {
    _ => ()
  }
}

///|
pub async fn readdir(
  dir : @fd_util.Fd,
  buf : FixedArray[Byte],
  len : Int,
  restart~ : Bool,
  context~ : String,
) -> Int {
  let job = Job::readdir(dir, buf, len, restart)
  perform_job_in_worker(job, context~)
}

///|
#cfg(not(platform="windows"))
pub async fn realpath(path : StringView, context~ : String) -> String {
  let path_bytes = @os_string.encode(path)
  let job = Job::realpath(path_bytes)
  let _ = perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  }
  let c_path = job.get_realpath_result()
  defer c_path.free()
  @os_string.decode(c_path)
}

///|
#cfg(platform="windows")
pub async fn realpath(path : StringView, context~ : String) -> String {
  let path_bytes = @os_string.encode(path)
  let job = Job::realpath(path_bytes)
  let _ = perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{path.escape()}")
    err => raise err
  }
  job.get_realpath_result()
}
