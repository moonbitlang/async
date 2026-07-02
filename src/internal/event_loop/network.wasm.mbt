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
async fn IoHandle::recvfrom_windows(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  let result = IoResult::for_socket_with_addr_read(
    buf,
    offset~,
    len~,
    flags=0,
    addr~,
  )
  defer result.free()
  handle.generic_read_windows(result, context~)
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
async fn IoHandle::sendto_windows(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  let result = IoResult::for_socket_with_addr_write(
    buf,
    offset~,
    len~,
    flags=0,
    addr~,
  )
  defer result.free()
  handle.generic_write_windows(result, context~)
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
fn IoResultHandle::connect_ffi(
  sock : @fd_util.Fd,
  result : IoResultHandle,
) -> Int = "moonbitlang/async" "socket/connect/windows"

///|
fn connect_windows_ffi(sock : @fd_util.Fd, result : IoResult) -> Int {
  IoResultHandle::connect_ffi(sock, result.handle)
}

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
fn IoResultHandle::accept_ffi(
  server_sock : @fd_util.Fd,
  conn_sock : @fd_util.Fd,
  result : IoResultHandle,
) -> Int = "moonbitlang/async" "socket/accept/windows"

///|
fn accept_windows_ffi(
  server_sock : @fd_util.Fd,
  conn_sock : @fd_util.Fd,
  result : IoResult,
) -> Int {
  IoResultHandle::accept_ffi(server_sock, conn_sock, result.handle)
}

///|
#unsafe_skip_stub_check
fn setup_accepted_socket_ffi(
  listen_sock : @fd_util.Fd,
  accept_sock : @fd_util.Fd,
) -> Int = "moonbitlang/async" "socket/setup_accepted_socket/windows"

///|
pub async fn IoHandle::accept_windows(
  handle : IoHandle,
  conn_sock : IoHandle,
  addr : Bytes,
  context~ : String,
) -> Unit {
  let result = IoResult::for_accept(addr.length())
  defer result.free()
  if 0 == accept_windows_ffi(handle.fd, conn_sock.fd, result) {
    if !@os_error.is_nonblocking_io_error() {
      @os_error.check_errno(context)
    }
    handle.wait_read_result(result, context~)
    ignore(result.status(handle.fd, context~))
  }
  result.get_accept_peer_addr(addr)
  if setup_accepted_socket_ffi(handle.fd, conn_sock.fd) < 0 {
    @os_error.check_errno(context)
  }
}
