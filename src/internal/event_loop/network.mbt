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
#borrow(buf, addr)
extern "C" fn recvfrom_ffi(
  fd : Int,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
) -> Int = "moonbitlang_async_recvfrom"

///|
pub async fn recvfrom(
  sock : Int,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  let handle = prepare_fd_read(sock)
  let ret = recvfrom_ffi(sock, buf, offset~, len~, addr~)
  let ret = if ret < 0 && @os_error.is_nonblocking_io_error() {
    handle.wait_read()
    recvfrom_ffi(sock, buf, offset~, len~, addr~)
  } else {
    @coroutine.pause()
    ret
  }
  if ret < 0 {
    @os_error.check_errno(context)
  }
  ret
}

///|
#borrow(buf, addr)
extern "C" fn sendto_ffi(
  fd : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
) -> Int = "moonbitlang_async_sendto"

///|
pub async fn sendto(
  sock : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  let handle = prepare_fd_write(sock)
  let ret = sendto_ffi(sock, buf, offset~, len~, addr~)
  let ret = if ret < 0 && @os_error.is_nonblocking_io_error() {
    handle.wait_write()
    sendto_ffi(sock, buf, offset~, len~, addr~)
  } else {
    @coroutine.pause()
    ret
  }
  if ret < 0 {
    @os_error.check_errno(context)
  }
  ret
}

///|
#borrow(addr)
extern "C" fn connect_ffi(sock : Int, addr : Bytes) -> Int = "moonbitlang_async_connect"

///|
extern "C" fn get_socket_err(sock : Int) -> Int = "moonbitlang_async_getsockerr"

///|
pub async fn connect(sock : Int, addr : Bytes, context~ : String) -> Int {
  let handle = prepare_fd_write(sock)
  if 0 == connect_ffi(sock, addr) {
    return 0
  }
  if @os_error.is_nonblocking_io_error() {
    handle.wait_write()
    let err = get_socket_err(sock)
    if err < 0 {
      @os_error.check_errno(context)
    } else if err > 0 {
      raise @os_error.OSError(err, context~, extra=None)
    }
  } else {
    @os_error.check_errno(context)
  }
  0
}

///|
#borrow(addr_buf)
extern "C" fn accept_ffi(sock : Int, addr_buf : Bytes) -> Int = "moonbitlang_async_accept"

///|
pub async fn accept(sock : Int, addr : Bytes, context~ : String) -> Int {
  let handle = prepare_fd_read(sock)
  let conn = accept_ffi(sock, addr)
  if conn > 0 {
    conn
  } else if @os_error.is_nonblocking_io_error() {
    handle.wait_read()
    accept_ffi(sock, addr)
  } else {
    @os_error.check_errno(context)
    -1
  }
}

///|
#external
pub type AddrInfo

///|
priv type AddrInfoRef

///|
extern "C" fn AddrInfoRef::new() -> AddrInfoRef = "moonbitlang_async_addrinfo_ref_make"

///|
#borrow(self)
extern "C" fn AddrInfoRef::get_and_clear(self : AddrInfoRef) -> AddrInfo = "moonbitlang_async_addrinfo_ref_get"

///|
extern "C" fn gai_strerror(code : Int) -> @c_buffer.Buffer = "gai_strerror"

///|
pub async fn getaddrinfo(
  host : StringView,
  context~ : String,
) -> Result[AddrInfo, String] {
  let host_bytes = @encoding/utf8.encode(host)
  let out = AddrInfoRef::new()
  let ret = perform_job_in_worker(
    JobForWorker::getaddrinfo(host_bytes, out),
    allow_cancel=true,
    context~,
    extra=Some(host),
  )
  if ret != 0 {
    let c_str = gai_strerror(ret)
    let len = c_str.strlen()
    let bytes = FixedArray::make(len, b'\x00')
    c_str.blit_to_bytes(dst=bytes, offset=0, len~)
    bytes.unsafe_reinterpret_as_bytes() |> @encoding/utf8.decode |> Err
  } else {
    Ok(out.get_and_clear())
  }
}
