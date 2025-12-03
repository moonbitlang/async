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
#borrow(path)
extern "C" fn open_ffi(path : Bytes, flags : Int, mode : Int) -> Int = "open"

///|
#borrow(stat)
extern "C" fn fstat_sync_ffi(fd : Int, stat : @fd_util.Stat) -> Int = "fstat"

///|
priv struct OpenJob {
  path : Bytes
  flags : Int
  mode : Int
  stat : @fd_util.Stat
  mut ret : Int
  mut err : Int
}

///|
pub async fn open(
  path : StringView,
  flags~ : Int,
  mode~ : Int,
  context~ : String,
) -> IoHandle {
  let path_bytes = @encoding/utf8.encode(path)
  let stat = @fd_util.Stat::new()
  let job : OpenJob = { path: path_bytes, flags, mode, stat, ret: 0, err: 0 }
  perform_job_in_worker(job, job => {
    job.ret = open_ffi(job.path, job.flags, job.mode)
    if job.ret < 0 {
      job.err = @os_error.get_errno()
      return
    }
    if fstat_sync_ffi(job.ret, job.stat) < 0 {
      job.err = @os_error.get_errno()
      return
    }
  })
  if job.ret < 0 {
    raise @os_error.OSError(job.err, context="\{context}: \{repr(path)}")
  }
  IoHandle::from_fd(job.ret, kind=job.stat.kind())
}

///|
#borrow(path, stat)
extern "C" fn stat_ffi(path : Bytes, stat : @fd_util.Stat) -> Int = "stat"

///|
#borrow(path, stat)
extern "C" fn lstat_ffi(path : Bytes, stat : @fd_util.Stat) -> Int = "lstat"

///|
priv struct StatJob {
  path : Bytes
  stat : @fd_util.Stat
  mut err : Int
}

///|
pub async fn stat(
  path : StringView,
  follow_symlink~ : Bool,
  context~ : String,
) -> @fd_util.Stat {
  let path_bytes = @encoding/utf8.encode(path)
  let stat = @fd_util.Stat::new()
  let job : StatJob = { path: path_bytes, stat, err: 0 }
  if follow_symlink {
    perform_job_in_worker(job, job => if stat_ffi(job.path, job.stat) < 0 {
      job.err = @os_error.get_errno()
    })
  } else {
    perform_job_in_worker(job, job => if lstat_ffi(job.path, job.stat) < 0 {
      job.err = @os_error.get_errno()
    })
  }
  if job.err != 0 {
    raise @os_error.OSError(job.err, context="\{context}: \{repr(path)}")
  }
  stat
}

///|
priv struct FstatJob {
  fd : Int
  stat : @fd_util.Stat
  mut err : Int
}

///|
pub async fn IoHandle::fstat(
  handle : IoHandle,
  context~ : String,
) -> @fd_util.Stat {
  let stat = @fd_util.Stat::new()
  let job : FstatJob = { fd: handle.fd, stat, err: 0 }
  perform_job_in_worker(job, job => if fstat_sync_ffi(job.fd, job.stat) < 0 {
    job.err = @os_error.get_errno()
  })
  if job.err != 0 {
    raise @os_error.OSError(job.err, context~)
  }
  stat
}

///|
#borrow(path)
extern "C" fn access_ffi(path : Bytes, amode : Int) -> Int = "access"

///|
priv struct AccessJob {
  path : Bytes
  amode : Int
  mut err : Int
}

///|
pub async fn access(path : StringView, amode~ : Int, context~ : String) -> Unit {
  let path_bytes = @encoding/utf8.encode(path)
  let job : AccessJob = { path: path_bytes, amode, err: 0 }
  perform_job_in_worker(job, job => if access_ffi(job.path, job.amode) < 0 {
    job.err = @os_error.get_errno()
  })
  if job.err != 0 {
    raise @os_error.OSError(job.err, context="\{context}: \{repr(path)}")
  }
}

///|
extern "C" fn fsync_ffi(fd : Int) -> Int = "fsync"

///|
extern "C" fn fdatasync_ffi(fd : Int) -> Int = "fdatasync"

///|
pub async fn IoHandle::fsync(
  handle : IoHandle,
  only_data~ : Bool,
  context~ : String,
) -> Unit {
  struct FsyncJob {
    fd : Int
    mut err : Int
  }
  let job : FsyncJob = { fd: handle.fd, err: 0 }
  if only_data {
    perform_job_in_worker(job, job => if fdatasync_ffi(job.fd) < 0 {
      job.err = @os_error.get_errno()
    })
  } else {
    perform_job_in_worker(job, job => if fsync_ffi(job.fd) < 0 {
      job.err = @os_error.get_errno()
    })
  }
  if job.err != 0 {
    raise @os_error.OSError(job.err, context~)
  }
}

///|
#borrow(path)
extern "C" fn remove_ffi(path : Bytes) -> Int = "remove"

///|
pub async fn remove(path : StringView, context~ : String) -> Unit {
  struct RemoveJob {
    path : Bytes
    mut err : Int
  }
  let path_bytes = @encoding/utf8.encode(path)
  let job : RemoveJob = { path: path_bytes, err: 0 }
  perform_job_in_worker(job, job => if remove_ffi(job.path) < 0 {
    job.err = @os_error.get_errno()
  })
  if job.err != 0 {
    raise @os_error.OSError(job.err, context="\{context}: \{repr(path)}")
  }
}

///|
#borrow(target, path)
extern "C" fn symlink_ffi(target : Bytes, path : Bytes) -> Int = "symlink"

///|
pub async fn symlink(
  target : StringView,
  path : StringView,
  context~ : String,
) -> Unit {
  struct Job {
    target : Bytes
    path : Bytes
    mut err : Int
  }
  let target_bytes = @encoding/utf8.encode(target)
  let path_bytes = @encoding/utf8.encode(path)
  let job : Job = { target: target_bytes, path: path_bytes, err: 0 }
  perform_job_in_worker(job, job => if symlink_ffi(job.target, job.path) < 0 {
    job.err = @os_error.get_errno()
  })
  if job.err != 0 {
    raise @os_error.OSError(
      job.err,
      context="\{context}: \{repr(target)} => \{repr(path)}",
    )
  }
}

///|
#borrow(path)
extern "C" fn mkdir_ffi(path : Bytes, mode : Int) -> Int = "mkdir"

///|
pub async fn mkdir(path : StringView, mode~ : Int, context~ : String) -> Unit {
  struct Job {
    path : Bytes
    mode : Int
    mut err : Int
  }
  let path_bytes = @encoding/utf8.encode(path)
  let job : Job = { path: path_bytes, mode, err: 0 }
  perform_job_in_worker(job, job => if mkdir_ffi(job.path, job.mode) < 0 {
    job.err = @os_error.get_errno()
  })
  if job.err != 0 {
    raise @os_error.OSError(job.err, context="\{context}: \{repr(path)}")
  }
}

///|
#borrow(path)
extern "C" fn rmdir_ffi(path : Bytes) -> Int = "rmdir"

///|
pub async fn rmdir(path : StringView, context~ : String) -> Unit {
  struct Job {
    path : Bytes
    mut err : Int
  }
  let path_bytes = @encoding/utf8.encode(path)
  let job : Job = { path: path_bytes, err: 0 }
  perform_job_in_worker(job, job => if rmdir_ffi(job.path) < 0 {
    job.err = @os_error.get_errno()
  })
  if job.err != 0 {
    raise @os_error.OSError(job.err, context="\{context}: \{repr(path)}")
  }
}

///|
#borrow(path, out)
extern "C" fn realpath_ffi(path : Bytes, out : Bytes?) -> @c_buffer.Buffer = "realpath"

///|
pub async fn realpath(path : StringView, context~ : String) -> Bytes {
  struct Job {
    path : Bytes
    mut result : @c_buffer.Buffer
    mut err : Int
  }
  let path_bytes = @encoding/utf8.encode(path)
  let job : Job = { path: path_bytes, result: @c_buffer.null, err: 0 }
  perform_job_in_worker(job, job => {
    job.result = realpath_ffi(job.path, None)
    if job.result.is_null() {
      job.err = @os_error.get_errno()
    }
  })
  if job.err != 0 {
    raise @os_error.OSError(job.err, context="\{context}: \{repr(path)}")
  }
  defer job.result.free()
  let len = job.result.strlen()
  let result = FixedArray::make(len, b'\x00')
  job.result.blit_to_bytes(dst=result, offset=0, len~)
  result.unsafe_reinterpret_as_bytes()
}
