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
pub struct AddrInfo(UInt64)

///|
#unsafe_skip_stub_check
fn gai_strerror(code : Int) -> @c_buffer.Buffer = "moonbitlang/async" "socket/gai_strerror"

///|
fn gai_error_to_string(code : Int) -> String {
  if platform is Windows {
    @os_error.errno_to_string(code)
  } else {
    let message = gai_strerror(code)
    defer message.free()
    @os_string.decode(message)
  }
}

///|
pub async fn getaddrinfo(
  host : StringView,
  context~ : String,
) -> Result[AddrInfo, String] {
  @coroutine.check_cancellation()
  let host_bytes = @os_string.encode(host)
  let job = Job::getaddrinfo(host_bytes)
  let mut result = Err("")
  let mut terminated = false
  defer {
    terminated = true
  }
  try
    @coroutine.spawn(() => {
      defer job.free()
      let ret = perform_job_in_worker(job, context~) catch {
        @os_error.OSError(errno, context~) =>
          raise @os_error.OSError(errno, context="\{context}: \{host.escape()}")
        err => raise err
      }
      guard !terminated else { return }
      if ret != 0 {
        result = Err(gai_error_to_string(ret))
      } else {
        result = Ok(job.get_getaddrinfo_result())
      }
    }).wait()
  catch {
    _ if result is Ok(_) => return result
    err => raise err
  } noraise {
    _ => result
  }
}

///|
pub async fn IoHandle::bind(
  handle : IoHandle,
  addr : Bytes,
  context~ : String,
) -> Unit {
  @coroutine.check_cancellation()
  let job = Job::bind(handle.fd, addr)
  defer job.free()
  ignore(perform_job_in_worker(job, context~))
}

///|
#unsafe_skip_stub_check
#borrow(buf, addr)
fn recvfrom_unix_ffi(
  fd : @fd_util.Fd,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  addr_len? : Int = addr.length(),
) -> Int = "moonbitlang/async" "socket/recvfrom/unix"

///|
async fn IoHandle::recvfrom_unix(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  let ret = recvfrom_unix_ffi(handle.fd, buf, offset~, len~, addr~)
  if ret >= 0 {
    @coroutine.protect_from_cancel(@coroutine.pause, resume_on_cancel=true)
    return ret
  }
  let ret = if @os_error.is_nonblocking_io_error() {
    handle.wait_read()
    recvfrom_unix_ffi(handle.fd, buf, offset~, len~, addr~)
  } else {
    ret
  }
  if ret < 0 {
    @os_error.check_errno(context)
  }
  ret
}

///|
async fn IoHandle::recvfrom_windows(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  let result = IoResult::for_socket_with_addr(ReadEvent, len~, flags=0, addr~)
  defer result.free()
  handle.generic_read_windows(result, buf, offset~, addr~, context~)
}

///|
pub async fn IoHandle::recvfrom(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  @coroutine.check_cancellation()
  if platform is Windows {
    handle.recvfrom_windows(buf, offset~, len~, addr~, context~)
  } else {
    handle.recvfrom_unix(buf, offset~, len~, addr~, context~)
  }
}

///|
#unsafe_skip_stub_check
#borrow(buf, addr)
fn sendto_unix_ffi(
  fd : @fd_util.Fd,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  addr_len? : Int = addr.length(),
) -> Int = "moonbitlang/async" "socket/sendto/unix"

///|
async fn IoHandle::sendto_unix(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  let ret = sendto_unix_ffi(handle.fd, buf, offset~, len~, addr~)
  if ret >= 0 {
    @coroutine.protect_from_cancel(@coroutine.pause, resume_on_cancel=true)
    return ret
  }
  let ret = if @os_error.is_nonblocking_io_error() {
    handle.wait_write()
    sendto_unix_ffi(handle.fd, buf, offset~, len~, addr~)
  } else {
    ret
  }
  if ret < 0 {
    @os_error.check_errno(context)
  }
  ret
}

///|
async fn IoHandle::sendto_windows(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  let result = IoResult::for_socket_with_addr(WriteEvent, len~, flags=0, addr~)
  defer result.free()
  handle.generic_write_windows(result, buf, offset~, len~, context~)
}

///|
pub async fn IoHandle::sendto(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  @coroutine.check_cancellation()
  if platform is Windows {
    handle.sendto_windows(buf, offset~, len~, addr~, context~)
  } else {
    handle.sendto_unix(buf, offset~, len~, addr~, context~)
  }
}

///|
#unsafe_skip_stub_check
#borrow(addr)
fn connect_unix_ffi(
  sock : @fd_util.Fd,
  addr : Bytes,
  addr_len? : Int = addr.length(),
) -> Int = "moonbitlang/async" "socket/connect/unix"

///|
#unsafe_skip_stub_check
fn get_socket_err(sock : @fd_util.Fd) -> Int = "moonbitlang/async" "socket/getsockerr/unix"

///|
async fn IoHandle::connect_unix(
  handle : IoHandle,
  addr : Bytes,
  context~ : String,
) -> Unit {
  if 0 == connect_unix_ffi(handle.fd, addr) {
    return
  }
  if @os_error.is_nonblocking_io_error() {
    handle.wait_write()
    let err = get_socket_err(handle.fd)
    if err < 0 {
      @os_error.check_errno(context)
    } else if err > 0 {
      raise @os_error.OSError(err, context~)
    }
  } else {
    @os_error.check_errno(context)
  }
}

///|
#unsafe_skip_stub_check
fn connect_windows_ffi(sock : @fd_util.Fd, result : IoResult) -> Int = "moonbitlang/async" "socket/connect/windows"

///|
#unsafe_skip_stub_check
fn setup_connected_socket_ffi(sock : @fd_util.Fd) -> Int = "moonbitlang/async" "socket/setup_connected_socket/windows"

///|
async fn IoHandle::connect_windows(
  handle : IoHandle,
  addr : Bytes,
  context~ : String,
) -> Unit {
  let result = IoResult::for_connect(addr)
  defer result.free()
  if 0 == connect_windows_ffi(handle.fd, result) {
    if !@os_error.is_nonblocking_io_error() {
      @os_error.check_errno(context)
    }
    handle.wait_write_result(result, context~)
    ignore(result.status(handle.fd, context~))
  }
  if setup_connected_socket_ffi(handle.fd) < 0 {
    @os_error.check_errno(context)
  }
}

///|
pub async fn IoHandle::connect(
  handle : IoHandle,
  addr : Bytes,
  context~ : String,
) -> Unit {
  @coroutine.check_cancellation()
  if platform is Windows {
    handle.connect_windows(addr, context~)
  } else {
    handle.connect_unix(addr, context~)
  }
}

///|
#unsafe_skip_stub_check
#borrow(addr_buf)
fn accept_unix_ffi(
  sock : @fd_util.Fd,
  addr_buf : Bytes,
  addr_len? : Int = addr_buf.length(),
) -> @fd_util.Fd = "moonbitlang/async" "socket/accept/unix"

///|
pub async fn IoHandle::accept_unix(
  handle : IoHandle,
  addr : Bytes,
  context~ : String,
) -> IoHandle {
  let conn = accept_unix_ffi(handle.fd, addr)
  let conn = if @fd_util.fd_is_valid(conn) {
    @coroutine.protect_from_cancel(@coroutine.pause, resume_on_cancel=true)
    conn
  } else if @os_error.is_nonblocking_io_error() {
    handle.wait_read()
    accept_unix_ffi(handle.fd, addr)
  } else {
    conn
  }
  if !@fd_util.fd_is_valid(conn) {
    @os_error.check_errno(context)
  }
  IoHandle::from_fd(conn, kind=Socket)
}

///|
#unsafe_skip_stub_check
fn accept_windows_ffi(
  server_sock : @fd_util.Fd,
  conn_sock : @fd_util.Fd,
  result : IoResult,
) -> Int = "moonbitlang/async" "socket/accept/windows"

///|
#unsafe_skip_stub_check
fn setup_accepted_socket_ffi(
  listen_sock : @fd_util.Fd,
  accept_sock : @fd_util.Fd,
) -> Int = "moonbitlang/async" "socket/setup_accepted_socket/windows"

///|
pub async fn IoHandle::accept_windows(
  handle : IoHandle,
  conn_sock : @fd_util.Fd,
  addr : Bytes,
  context~ : String,
) -> IoHandle {
  let result = IoResult::for_accept(addr.length())
  defer result.free()
  if 0 == accept_windows_ffi(handle.fd, conn_sock, result) {
    if !@os_error.is_nonblocking_io_error() {
      @os_error.check_errno(context)
    }
    handle.wait_read_result(result, context~)
    ignore(result.status(handle.fd, context~))
  }
  result.get_accept_peer_addr(addr)
  if setup_accepted_socket_ffi(handle.fd, conn_sock) < 0 {
    @os_error.check_errno(context)
  }
  IoHandle::from_fd(conn_sock, kind=Socket)
}
