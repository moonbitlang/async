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
#cfg(platform="windows")
extern "C" fn init_WSA_ffi() -> Int = "moonbitlang_async_init_WSA"

///|
#cfg(platform="windows")
extern "C" fn cleanup_WSA_ffi() -> Int = "WSACleanup"

///|
#cfg(not(platform="windows"))
#borrow(buf, addr)
extern "C" fn recvfrom_ffi(
  fd : @fd_util.Fd,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
) -> Int = "moonbitlang_async_recvfrom"

///|
#cfg(not(platform="windows"))
pub async fn IoHandle::recvfrom(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  handle.prepare_read()
  let ret = recvfrom_ffi(handle.fd, buf, offset~, len~, addr~)
  if ret >= 0 {
    @coroutine.pause()
    return ret
  }
  let ret = if @os_error.is_nonblocking_io_error() {
    handle.wait_read()
    recvfrom_ffi(handle.fd, buf, offset~, len~, addr~)
  } else {
    ret
  }
  if ret < 0 {
    @os_error.check_errno(context)
  }
  ret
}

///|
#cfg(platform="windows")
pub async fn IoHandle::recvfrom(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  guard curr_loop.val is Some(evloop)
  guard !handle.reading
  handle.reading = true
  defer {
    handle.reading = false
  }
  let job_id = evloop.job_id
  evloop.job_id += 1
  let result = IoResult::for_socket_with_addr(
    job_id,
    buf.unsafe_reinterpret_as_bytes(),
    offset~,
    len~,
    flags=0,
    addr~,
  )
  defer result.free()
  handle.generic_read(job_id, result, context~)
}

///|
#cfg(not(platform="windows"))
#borrow(buf, addr)
extern "C" fn sendto_ffi(
  fd : @fd_util.Fd,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
) -> Int = "moonbitlang_async_sendto"

///|
#cfg(not(platform="windows"))
pub async fn IoHandle::sendto(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  handle.prepare_write()
  let ret = sendto_ffi(handle.fd, buf, offset~, len~, addr~)
  if ret >= 0 {
    @coroutine.pause()
    return ret
  }
  let ret = if @os_error.is_nonblocking_io_error() {
    handle.wait_write()
    sendto_ffi(handle.fd, buf, offset~, len~, addr~)
  } else {
    ret
  }
  if ret < 0 {
    @os_error.check_errno(context)
  }
  ret
}

///|
#cfg(platform="windows")
pub async fn IoHandle::sendto(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  guard curr_loop.val is Some(evloop)
  guard !handle.writing
  handle.writing = true
  defer {
    handle.writing = false
  }
  let job_id = evloop.job_id
  evloop.job_id += 1
  let result = IoResult::for_socket_with_addr(
    job_id,
    buf,
    offset~,
    len~,
    flags=0,
    addr~,
  )
  defer result.free()
  handle.generic_write(job_id, result, context~)
}

///|
#cfg(not(platform="windows"))
#borrow(addr)
extern "C" fn connect_ffi(sock : @fd_util.Fd, addr : Bytes) -> Int = "moonbitlang_async_connect"

///|
#cfg(not(platform="windows"))
extern "C" fn get_socket_err(sock : @fd_util.Fd) -> Int = "moonbitlang_async_getsockerr"

///|
#cfg(not(platform="windows"))
pub async fn IoHandle::connect(
  handle : IoHandle,
  addr : Bytes,
  context~ : String,
) -> Unit {
  handle.prepare_write()
  if 0 == connect_ffi(handle.fd, addr) {
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
#cfg(platform="windows")
extern "C" fn connect_ffi(sock : @fd_util.Fd, result : IoResult) -> Int = "moonbitlang_async_connect"

///|
#cfg(platform="windows")
extern "C" fn setup_connected_socket_ffi(sock : @fd_util.Fd) -> Int = "moonbitlang_async_setup_connected_socket"

///|
#cfg(platform="windows")
pub async fn IoHandle::connect(
  handle : IoHandle,
  addr : Bytes,
  context~ : String,
) -> Unit {
  guard curr_loop.val is Some(evloop)
  guard !handle.writing
  handle.writing = true
  defer {
    handle.writing = false
  }
  let job_id = evloop.job_id
  evloop.job_id += 1
  let result = IoResult::for_connect(job_id, addr)
  defer result.free()
  if 0 == connect_ffi(handle.fd, result) {
    if !@os_error.is_nonblocking_io_error() {
      @os_error.check_errno(context)
    }
    evloop.wait_for_io_result(job_id, result, handle.fd, context~)
    ignore(result.status(handle.fd, context~))
  }
  if setup_connected_socket_ffi(handle.fd) < 0 {
    @os_error.check_errno(context)
  }
}

///|
#cfg(not(platform="windows"))
#borrow(addr_buf)
extern "C" fn accept_ffi(sock : @fd_util.Fd, addr_buf : Bytes) -> Int = "moonbitlang_async_accept"

///|
#cfg(not(platform="windows"))
pub async fn IoHandle::accept(
  handle : IoHandle,
  addr : Bytes,
  context~ : String,
) -> IoHandle {
  handle.prepare_read()
  let conn = accept_ffi(handle.fd, addr)
  let conn = if conn >= 0 {
    conn
  } else if @os_error.is_nonblocking_io_error() {
    handle.wait_read()
    accept_ffi(handle.fd, addr)
  } else {
    conn
  }
  if conn < 0 {
    @os_error.check_errno(context)
  }
  IoHandle::from_fd(conn, kind=Socket)
}

///|
#cfg(platform="windows")
extern "C" fn accept_ffi(
  server_sock : @fd_util.Fd,
  conn_sock : @fd_util.Fd,
  result : IoResult,
) -> Int = "moonbitlang_async_accept"

///|
#cfg(platform="windows")
extern "C" fn setup_accepted_socket_ffi(
  listen_sock : @fd_util.Fd,
  accept_sock : @fd_util.Fd,
) -> Int = "moonbitlang_async_setup_accepted_socket"

///|
#cfg(platform="windows")
pub async fn IoHandle::accept(
  handle : IoHandle,
  conn_sock : @fd_util.Fd,
  context~ : String,
) -> IoHandle {
  guard curr_loop.val is Some(evloop)
  guard !handle.reading
  handle.reading = true
  defer {
    handle.reading = false
  }
  let job_id = evloop.job_id
  evloop.job_id += 1
  let result = IoResult::for_accept(job_id)
  defer result.free()
  if 0 == accept_ffi(handle.fd, conn_sock, result) {
    if !@os_error.is_nonblocking_io_error() {
      @os_error.check_errno(context)
    }
    evloop.wait_for_io_result(job_id, result, handle.fd, context~)
    ignore(result.status(handle.fd, context~))
  }
  if setup_accepted_socket_ffi(handle.fd, conn_sock) < 0 {
    @os_error.check_errno(context)
  }
  IoHandle::from_fd(conn_sock, kind=Socket)
}

///|
#external
pub type AddrInfo

///|
#cfg(not(platform="windows"))
extern "C" fn gai_strerror(code : Int) -> @c_buffer.Buffer = "gai_strerror"

///|
#cfg(not(platform="windows"))
fn gai_error_to_string(code : Int) -> String {
  @os_string.decode(gai_strerror(code))
}

///|
#cfg(platform="windows")
fn gai_error_to_string(code : Int) -> String {
  @os_error.errno_to_string(code)
}

///|
pub async fn getaddrinfo(
  host : StringView,
  context~ : String,
) -> Result[AddrInfo, String] {
  let host_bytes = @os_string.encode(host)
  let job = Job::getaddrinfo(host_bytes)
  let ret = perform_job_in_worker(job, cancel=Ignore, context~) catch {
    @os_error.OSError(errno, context~) =>
      raise @os_error.OSError(errno, context="\{context}: \{repr(host)}")
    err => raise err
  }
  if ret != 0 {
    Err(gai_error_to_string(ret))
  } else {
    Ok(job.get_getaddrinfo_result())
  }
}
