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

/// Receives data from a socket asynchronously, optionally retrieving sender address.
/// 
/// This function performs a non-blocking receive operation on a socket,
/// integrating with the event loop for efficient I/O handling.
/// 
/// # Parameters
/// - `sock`: Socket file descriptor to receive from
/// - `buf`: Buffer to store received data
/// - `offset`: Offset within buffer to start writing
/// - `len`: Maximum number of bytes to receive
/// - `addr`: Buffer to store sender address (optional)
/// - `context`: Error context for debugging
/// 
/// # Returns
/// Number of bytes received
/// 
/// # Errors
/// Raises OSError on receive failures
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

/// Sends data to a socket asynchronously, optionally specifying destination address.
/// 
/// This function performs a non-blocking send operation on a socket,
/// integrating with the event loop for efficient I/O handling.
/// 
/// # Parameters
/// - `sock`: Socket file descriptor to send to
/// - `buf`: Buffer containing data to send
/// - `offset`: Offset within buffer to start reading from
/// - `len`: Number of bytes to send
/// - `addr`: Destination address (optional)
/// - `context`: Error context for debugging
/// 
/// # Returns
/// Number of bytes sent
/// 
/// # Errors
/// Raises OSError on send failures
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

/// Connects a socket to a remote address asynchronously.
/// 
/// This function initiates a connection to the specified address.
/// For non-blocking sockets, it handles the asynchronous connection process.
/// 
/// # Parameters
/// - `sock`: Socket file descriptor
/// - `addr`: Address to connect to
/// - `context`: Error context for debugging
/// 
/// # Returns
/// 0 on successful connection
/// 
/// # Errors
/// Raises OSError on connection failures
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
      raise @os_error.OSError(err, context~)
    }
  } else {
    @os_error.check_errno(context)
  }
  0
}

///|
#borrow(addr_buf)
extern "C" fn accept_ffi(sock : Int, addr_buf : Bytes) -> Int = "moonbitlang_async_accept"

/// Accepts an incoming connection on a listening socket asynchronously.
/// 
/// This function waits for and accepts the next pending connection
/// on the specified listening socket.
/// 
/// # Parameters
/// - `sock`: Listening socket file descriptor
/// - `addr`: Buffer to store client address
/// - `context`: Error context for debugging
/// 
/// # Returns
/// File descriptor of the accepted connection
/// 
/// # Errors
/// Raises OSError on accept failures
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

/// Address information structure for network operations.
/// 
/// This opaque type contains address information returned by `getaddrinfo`,
/// including IP addresses, port numbers, and socket types. It is used for
/// network address resolution and socket operations.
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

/// Resolves a hostname to network address information asynchronously.
/// 
/// This function performs DNS resolution and returns address information
/// suitable for creating sockets and establishing connections.
/// 
/// # Parameters
/// - `host`: Hostname or IP address to resolve
/// - `context`: Error context for debugging
/// 
/// # Returns
/// Result containing AddrInfo on success or error message on failure
/// 
/// # Example
/// ```moonbit
/// match getaddrinfo("example.com", context~="resolve") {
///   Ok(addr_info) => // Use address info for connection
///   Err(error) => println("Resolution failed: " + error)
/// }
/// ```
///|
pub async fn getaddrinfo(
  host : StringView,
  context~ : String,
) -> Result[AddrInfo, String] {
  let host = @encoding/utf8.encode(host)
  let out = AddrInfoRef::new()
  let ret = perform_job_in_worker(
    JobForWorker::getaddrinfo(host, out),
    allow_cancel=true,
    context~,
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
