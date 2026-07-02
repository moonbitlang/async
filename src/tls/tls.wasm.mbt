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
priv struct TlsConnectionHandle(UInt64)

///|
priv struct TlsContextHandle(UInt64)

///|
const TRUST_NO_VERIFICATION = 0

///|
const TRUST_SYSTEM_ROOT = 1

///|
const TRUST_CUSTOM_ROOT = 2

///|
const TLS_STATUS_ERROR = -1

///|
const TLS_STATUS_CLOSED = -2

///|
const TLS_STATUS_WOULD_BLOCK = -3

///|
fn TlsConnectionHandle::is_null(self : TlsConnectionHandle) -> Bool {
  self.0 == 0UL
}

///|
fn TlsContextHandle::is_null(self : TlsContextHandle) -> Bool {
  self.0 == 0UL
}

///|
fn TrustedRoot::mode(self : TrustedRoot) -> Int {
  match self {
    NoVerification => TRUST_NO_VERIFICATION
    SystemRoot => TRUST_SYSTEM_ROOT
    CustomPemFile(_) => TRUST_CUSTOM_ROOT
  }
}

///|
fn @c_buffer.Buffer::to_utf8_string(buf : @c_buffer.Buffer) -> String {
  defer buf.free()
  let len = buf.strlen()
  let bytes = FixedArray::make(len, b'\x00')
  buf.blit_to_bytes(dst=bytes, len~)
  @utf8.decode(bytes.unsafe_reinterpret_as_bytes()) catch {
    _ => "invalid UTF-8 TLS error message"
  }
}

///|
#unsafe_skip_stub_check
fn TlsContextHandle::client_new(trust : Int) -> TlsContextHandle = "moonbitlang/async" "tls/context/client_new"

///|
#unsafe_skip_stub_check
#borrow(private_key_file, certificate_file)
fn TlsContextHandle::server_new(
  private_key_file : Bytes,
  private_key_file_len? : Int = private_key_file.length(),
  private_key_type : X509FileType,
  certificate_file : Bytes,
  certificate_file_len? : Int = certificate_file.length(),
  certificate_type : X509FileType,
) -> TlsContextHandle = "moonbitlang/async" "tls/context/server_new"

///|
#unsafe_skip_stub_check
#borrow(pfx_file)
fn TlsContextHandle::server_pfx_new(
  pfx_file : Bytes,
  pfx_file_len? : Int = pfx_file.length(),
) -> TlsContextHandle = "moonbitlang/async" "tls/context/server_pfx_new"

///|
#unsafe_skip_stub_check
fn TlsContextHandle::free_ffi(self : TlsContextHandle) -> Unit = "moonbitlang/async" "tls/context/free"

///|
fn TlsContextHandle::free(self : TlsContextHandle) -> Unit {
  if self.0 != 0UL {
    self.free_ffi()
  }
}

///|
#unsafe_skip_stub_check
#borrow(cert)
fn TlsContextHandle::add_certificate(
  self : TlsContextHandle,
  cert : Bytes,
  offset? : Int = 0,
  len? : Int = cert.length(),
) -> Int = "moonbitlang/async" "tls/context/add_certificate"

///|
#unsafe_skip_stub_check
fn TlsContextHandle::take_error(self : TlsContextHandle) -> @c_buffer.Buffer = "moonbitlang/async" "tls/context/take_error"

///|
fn TlsContextHandle::check(
  self : TlsContextHandle,
  status : Int,
) -> Unit raise TlsError {
  if status == TLS_STATUS_ERROR {
    raise TlsError(self.take_error().to_utf8_string())
  }
}

///|
fn TlsContextHandle::check_new(
  self : TlsContextHandle,
) -> TlsContextHandle raise TlsError {
  if self.is_null() {
    raise TlsError(tls_take_global_error().to_utf8_string())
  }
  self
}

///|
#unsafe_skip_stub_check
#borrow(host)
fn TlsConnectionHandle::client_new(
  host : Bytes,
  host_len? : Int = host.length(),
  sni~ : Bool,
  context : TlsContextHandle,
) -> TlsConnectionHandle = "moonbitlang/async" "tls/connection/client_new"

///|
#unsafe_skip_stub_check
fn TlsConnectionHandle::server_new(
  context : TlsContextHandle,
) -> TlsConnectionHandle = "moonbitlang/async" "tls/connection/server_new"

///|
#unsafe_skip_stub_check
fn tls_take_global_error() -> @c_buffer.Buffer = "moonbitlang/async" "tls/error/take_global"

///|
#unsafe_skip_stub_check
fn TlsConnectionHandle::free_ffi(self : TlsConnectionHandle) -> Unit = "moonbitlang/async" "tls/connection/free"

///|
fn TlsConnectionHandle::free(self : TlsConnectionHandle) -> Unit {
  if !self.is_null() {
    self.free_ffi()
  }
}

///|
#unsafe_skip_stub_check
fn TlsConnectionHandle::take_error(
  self : TlsConnectionHandle,
) -> @c_buffer.Buffer = "moonbitlang/async" "tls/connection/take_error"

///|
#unsafe_skip_stub_check
#borrow(src)
fn TlsConnectionHandle::read_tls(
  self : TlsConnectionHandle,
  src : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang/async" "tls/connection/read_tls"

///|
#unsafe_skip_stub_check
#borrow(dst)
fn TlsConnectionHandle::write_tls(
  self : TlsConnectionHandle,
  dst : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang/async" "tls/connection/write_tls"

///|
#unsafe_skip_stub_check
#borrow(dst)
fn TlsConnectionHandle::read_plain(
  self : TlsConnectionHandle,
  dst : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang/async" "tls/connection/read_plain"

///|
#unsafe_skip_stub_check
#borrow(src)
fn TlsConnectionHandle::write_plain(
  self : TlsConnectionHandle,
  src : Bytes,
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang/async" "tls/connection/write_plain"

///|
#unsafe_skip_stub_check
fn TlsConnectionHandle::wants_read(self : TlsConnectionHandle) -> Bool = "moonbitlang/async" "tls/connection/wants_read"

///|
#unsafe_skip_stub_check
fn TlsConnectionHandle::wants_write(self : TlsConnectionHandle) -> Bool = "moonbitlang/async" "tls/connection/wants_write"

///|
#unsafe_skip_stub_check
fn TlsConnectionHandle::is_handshaking(self : TlsConnectionHandle) -> Bool = "moonbitlang/async" "tls/connection/is_handshaking"

///|
#unsafe_skip_stub_check
fn TlsConnectionHandle::send_close_notify(self : TlsConnectionHandle) -> Unit = "moonbitlang/async" "tls/connection/send_close_notify"

///|
#unsafe_skip_stub_check
fn TlsConnectionHandle::peer_certificate_len(self : TlsConnectionHandle) -> Int = "moonbitlang/async" "tls/connection/peer_certificate_len"

///|
#unsafe_skip_stub_check
#borrow(dst)
fn TlsConnectionHandle::peer_certificate(
  self : TlsConnectionHandle,
  dst : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang/async" "tls/connection/peer_certificate"

///|
fn TlsConnectionHandle::check_new(
  self : TlsConnectionHandle,
) -> TlsConnectionHandle raise TlsError {
  if self.is_null() {
    raise TlsError(tls_take_global_error().to_utf8_string())
  }
  self
}

///|
fn TlsConnectionHandle::check_status(
  self : TlsConnectionHandle,
  status : Int,
) -> Unit raise {
  if status == TLS_STATUS_ERROR {
    raise TlsError(self.take_error().to_utf8_string())
  }
}

///|
fn TlsConnectionHandle::check_read_status(
  self : TlsConnectionHandle,
  status : Int,
) -> Unit raise {
  match status {
    TLS_STATUS_ERROR => raise TlsError(self.take_error().to_utf8_string())
    TLS_STATUS_CLOSED => raise ConnectionClosed
    _ => ()
  }
}

///|
struct Tls {
  conn : TlsConnectionHandle
  host : String?
  is_client : Bool
  transport : Transport
  read_buf : @io.ReaderBuffer
  mut shutdown : Bool
  mut closed : Bool
}

///|
fn[R : @io.Reader, W : @io.Writer] Tls::from_pair(
  conn : TlsConnectionHandle,
  r : R,
  w : W,
  is_client~ : Bool,
  host~ : String?,
) -> Tls {
  {
    conn,
    host,
    is_client,
    transport: Transport::new(r, w),
    read_buf: @io.ReaderBuffer::new(),
    shutdown: false,
    closed: false,
  }
}

///|
async fn Tls::read_tls_input(self : Tls) -> Bool {
  let read_buf = self.transport.reader._get_internal_buffer().repr()
  if read_buf.len == 0 {
    if self.transport.state is Closed {
      return false
    }
    self.transport.read_more()
  }
  let n = self.conn.read_tls(
    read_buf.buf,
    offset=read_buf.start,
    len=read_buf.len,
  )
  self.conn.check_read_status(n)
  if n == 0 {
    return false
  }
  read_buf.drop(n)
  true
}

///|
async fn Tls::drain_tls_output_unlocked(self : Tls) -> Unit {
  let output = FixedArray::make(BUFFER_SIZE, b'\x00')
  while self.conn.write_tls(output, offset=0, len=output.length()) is n {
    match n {
      n if n > 0 => {
        let data = output.unsafe_reinterpret_as_bytes()[:n]
        self.transport.writer.write(data)
      }
      0 => break
      TLS_STATUS_WOULD_BLOCK => break
      TLS_STATUS_CLOSED => raise ConnectionClosed
      TLS_STATUS_ERROR =>
        raise TlsError(self.conn.take_error().to_utf8_string())
      _ => abort("unexpected status code \{n} from TLS output")
    }
  }
}

///|
async fn Tls::drain_tls_output(self : Tls) -> Unit {
  self.transport.write_lock.acquire()
  defer self.transport.write_lock.release()
  self.drain_tls_output_unlocked()
}

///|
async fn Tls::handshake(self : Tls) -> Unit {
  while self.conn.is_handshaking() {
    self.drain_tls_output()
    if self.conn.is_handshaking() {
      if self.conn.wants_read() {
        guard self.read_tls_input() else { raise ConnectionClosed }
      } else if !self.conn.wants_write() {
        raise TlsError("TLS handshake stalled")
      }
    }
  }
  self.drain_tls_output()
}

///|
async fn client_context_from_trust(trust : TrustedRoot) -> TlsContextHandle {
  let context = TlsContextHandle::client_new(trust.mode()).check_new()
  try {
    match trust {
      CustomPemFile(path) => {
        let pem = @fs.read_file(path).text()
        for cert in decode_pem_certificates(pem) {
          context.check(context.add_certificate(cert))
        }
      }
      _ => ()
    }
    context
  } catch {
    err => {
      context.free()
      raise err
    }
  }
}

///|
#label_migration(verify, fill=false, msg="use `trust` instead")
pub async fn[R : @io.Reader, W : @io.Writer] Tls::client_from_pair(
  r : R,
  w : W,
  verify? : Bool = true,
  host? : String,
  sni? : Bool = true,
  trust? : TrustedRoot,
) -> Tls {
  let trust = match trust {
    Some(trust) => trust
    None => if verify { SystemRoot } else { NoVerification }
  }
  let context = client_context_from_trust(trust)
  defer context.free()
  let host_bytes = match host {
    Some(host) => @utf8.encode(host)
    None => b""
  }
  let conn = TlsConnectionHandle::client_new(host_bytes, sni~, context).check_new()
  let self = Tls::from_pair(conn, r, w, is_client=true, host~)
  try {
    self.handshake()
    self
  } catch {
    err => {
      self.close()
      raise err
    }
  }
}

///|
#internal(internal, "do not use, for internal testing only")
pub async fn[R : @io.Reader, W : @io.Writer] Tls::server_from_pair(
  r : R,
  w : W,
  private_key_file? : String,
  private_key_type? : X509FileType,
  certificate_file? : String,
  certificate_type? : X509FileType,
  pfx_file? : String,
) -> Tls {
  let context = if @event_loop.platform is Windows {
    let pfx_file = match pfx_file {
      Some(pfx_file) => pfx_file
      None =>
        raise TlsError("pfx_file is required for TLS servers on Windows hosts")
    }
    let pfx_file = @utf8.encode(pfx_file)
    TlsContextHandle::server_pfx_new(pfx_file).check_new()
  } else {
    let private_key_file = match private_key_file {
      Some(private_key_file) => private_key_file
      None =>
        raise TlsError(
          "private_key_file is required for TLS servers on non-Windows hosts",
        )
    }
    let certificate_file = match certificate_file {
      Some(certificate_file) => certificate_file
      None =>
        raise TlsError(
          "certificate_file is required for TLS servers on non-Windows hosts",
        )
    }
    let private_key_type = match private_key_type {
      Some(private_key_type) => private_key_type
      None =>
        raise TlsError(
          "private_key_type is required for TLS servers on non-Windows hosts",
        )
    }
    let certificate_type = match certificate_type {
      Some(certificate_type) => certificate_type
      None =>
        raise TlsError(
          "certificate_type is required for TLS servers on non-Windows hosts",
        )
    }
    let private_key_file = @utf8.encode(private_key_file)
    let certificate_file = @utf8.encode(certificate_file)
    TlsContextHandle::server_new(
      private_key_file, private_key_type, certificate_file, certificate_type,
    ).check_new()
  }
  defer context.free()
  let conn = TlsConnectionHandle::server_new(context).check_new()
  let self = Tls::from_pair(conn, r, w, is_client=false, host=None)
  try {
    self.handshake()
    self
  } catch {
    err => {
      self.close()
      raise err
    }
  }
}

///|
#internal(internal, "do not use, for internal testing only")
pub async fn[Inner : @io.Reader + @io.Writer] Tls::server(
  inner : Inner,
  private_key_file? : String,
  private_key_type? : X509FileType,
  certificate_file? : String,
  certificate_type? : X509FileType,
  pfx_file? : String,
) -> Tls {
  Tls::server_from_pair(
    inner,
    inner,
    private_key_file?,
    private_key_type?,
    certificate_file?,
    certificate_type?,
    pfx_file?,
  )
}

///|
pub impl @io.Reader for Tls with fn _direct_read(self, buf, offset~, max_len~) {
  while self.conn.read_plain(buf, offset~, len=max_len) is n {
    match n {
      n if n > 0 => {
        self.drain_tls_output()
        return n
      }
      TLS_STATUS_CLOSED => {
        self.shutdown()
        return 0
      }
      TLS_STATUS_WOULD_BLOCK => {
        self.drain_tls_output()
        if self.transport.state is Closed &&
          self.transport.reader._get_internal_buffer().repr().len == 0 {
          return 0
        }
        if self.conn.wants_read() {
          guard self.read_tls_input() else { return 0 }
        } else if !self.conn.wants_write() {
          return 0
        }
      }
      TLS_STATUS_ERROR =>
        raise TlsError(self.conn.take_error().to_utf8_string())
      _ => abort("unexpected status code \{n} from TLS read")
    }
  } nobreak {
    0
  }
}

///|
pub impl @io.Reader for Tls with fn _get_internal_buffer(self) {
  self.read_buf
}

///|
pub impl @io.Writer for Tls with fn write_once(self, buf, offset~, len~) {
  self.transport.write_lock.acquire()
  defer self.transport.write_lock.release()
  while self.conn.write_plain(buf, offset~, len~) is n {
    match n {
      n if n >= 0 => {
        self.drain_tls_output_unlocked()
        return n
      }
      TLS_STATUS_WOULD_BLOCK => {
        self.drain_tls_output_unlocked()
        if self.conn.wants_read() {
          guard self.read_tls_input() else { raise ConnectionClosed }
        }
      }
      TLS_STATUS_CLOSED => raise ConnectionClosed
      TLS_STATUS_ERROR =>
        raise TlsError(self.conn.take_error().to_utf8_string())
      _ => abort("unexpected status code \{n} from TLS write")
    }
  } nobreak {
    0
  }
}

///|
pub fn Tls::close(self : Tls) -> Unit {
  guard !self.closed else {  }
  self.closed = true
  if self.transport.state is Normal {
    self.transport.state = Closed
  }
  self.conn.free()
  ignore(self.host)
}

///|
pub async fn Tls::shutdown(self : Tls) -> Unit {
  guard !self.shutdown else {  }
  self.shutdown = true
  match self.transport.state {
    Normal => ()
    Closed => raise ConnectionClosed
    Error(err) => raise err
  }
  self.conn.send_close_notify()
  self.drain_tls_output()
}

///|
pub fn Tls::get_peer_certificate(self : Tls) -> Bytes? raise {
  let len = self.conn.peer_certificate_len()
  self.conn.check_status(len)
  guard len > 0
  let result = FixedArray::make(len, b'\x00')
  self.conn.check_status(self.conn.peer_certificate(result, offset=0, len~))
  Some(result.unsafe_reinterpret_as_bytes())
}

///|
pub fn Tls::unique_channel_binding(_self : Tls) -> Bytes raise {
  raise TlsError("tls-unique channel binding unavailable on wasm")
}

///|
pub fn Tls::server_endpoint_channel_binding(_self : Tls) -> Bytes raise {
  raise TlsError("tls-server-endpoint channel binding unavailable on wasm")
}

///|
let _unused : Unit = {
  ignore(@bytes_util.ascii_to_string)
  ignore(@os_error.check_errno)
  ignore(@os_string.encode)
  ignore((tls : Tls) => tls.is_client)
  ignore((transport : Transport) => transport.flush_write())
  ignore((_ : @fs.File) => ())
}
