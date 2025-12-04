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
#external
pub type Directory

///|
#external
pub type DirectoryEntry

///|
pub async fn open(
  path : StringView,
  flags~ : Int,
  mode~ : Int,
  context~ : String,
) -> IoHandle {
  let path_bytes = @encoding/utf8.encode(path)
  let job = Job::open(path_bytes, flags, mode)
  try perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{repr(path)}")
    err => raise err
  } noraise {
    fd => {
      let kind = @fd_util.FileKind::from_sys_kind(job.get_open_job_kind())
      IoHandle::from_fd(fd, kind~)
    }
  }
}

///|
pub async fn file_kind_by_path(
  path : StringView,
  follow_symlink~ : Bool,
  context~ : String,
) -> @fd_util.FileKind {
  let path_bytes = @encoding/utf8.encode(path)
  let job = Job::file_kind_by_path(path_bytes, follow_symlink~)
  try perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{repr(path)}")
    err => raise err
  } noraise {
    sys_kind => @fd_util.FileKind::from_sys_kind(sys_kind)
  }
}

///|
pub async fn file_size(fd : Int, context~ : String) -> Int64 {
  let job = Job::file_size(fd)
  let _ = perform_job_in_worker(job, context~)
  job.get_file_size_result()
}

///|
pub async fn file_time(fd : Int, context~ : String) -> @fd_util.FileTime {
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
  let path_bytes = @encoding/utf8.encode(path)
  let result = @fd_util.FileTime::new()
  let job = Job::file_time_by_path(path_bytes, result, follow_symlink~)
  try perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{repr(path)}")
    err => raise err
  } noraise {
    _ => ()
  }
  result
}

///|
pub async fn IoHandle::seek(
  handle : IoHandle,
  offset : Int64,
  whence : Int,
  context~ : String,
) -> Int64 {
  let job = Job::seek(handle.fd, offset, whence)
  let _ = perform_job_in_worker(job, context~)
  job.get_seek_result()
}

///|
pub async fn access(path : StringView, amode~ : Int, context~ : String) -> Int {
  let path_bytes = @encoding/utf8.encode(path)
  perform_job_in_worker(Job::access(path_bytes, amode), context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{repr(path)}")
    err => raise err
  }
}

///|
pub async fn chmod(path : StringView, mode : Int, context~ : String) -> Unit {
  let path_bytes = @encoding/utf8.encode(path)
  try perform_job_in_worker(Job::chmod(path_bytes, mode), context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{repr(path)}")
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
pub async fn remove(path : StringView, context~ : String) -> Unit {
  let path_bytes = @encoding/utf8.encode(path)
  try perform_job_in_worker(Job::remove(path_bytes), context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{repr(path)}")
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
  let target_bytes = @encoding/utf8.encode(target)
  let path_bytes = @encoding/utf8.encode(path)
  try
    perform_job_in_worker(Job::symlink(target_bytes, path_bytes), context~)
  catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(
        errno,
        context="\{context}: \{repr(target)} => \{repr(path)}",
      )
    err => raise err
  } noraise {
    _ => ()
  }
}

///|
pub async fn mkdir(path : StringView, mode~ : Int, context~ : String) -> Unit {
  let path_bytes = @encoding/utf8.encode(path)
  try perform_job_in_worker(Job::mkdir(path_bytes, mode), context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{repr(path)}")
    err => raise err
  } noraise {
    _ => ()
  }
}

///|
pub async fn rmdir(path : StringView, context~ : String) -> Unit {
  let path_bytes = @encoding/utf8.encode(path)
  try perform_job_in_worker(Job::rmdir(path_bytes), context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{repr(path)}")
    err => raise err
  } noraise {
    _ => ()
  }
}

///|
pub async fn opendir(path : StringView, context~ : String) -> Directory {
  let path_bytes = @encoding/utf8.encode(path)
  let job = Job::opendir(path_bytes)
  let _ = perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{repr(path)}")
    err => raise err
  }
  job.get_opendir_result()
}

///|
pub async fn readdir(dir : Directory, context~ : String) -> DirectoryEntry {
  let job = Job::readdir(dir)
  let _ = perform_job_in_worker(job, context~)
  job.get_readdir_result()
}

///|
pub async fn realpath(path : StringView, context~ : String) -> Bytes {
  let path_bytes = @encoding/utf8.encode(path)
  let job = Job::realpath(path_bytes)
  let _ = perform_job_in_worker(job, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{repr(path)}")
    err => raise err
  }
  let c_path = job.get_realpath_result()
  defer c_path.free()
  let len = c_path.strlen()
  let result = FixedArray::make(len, b'\x00')
  c_path.blit_to_bytes(dst=result, offset=0, len~)
  result.unsafe_reinterpret_as_bytes()
}
