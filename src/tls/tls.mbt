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
/// A TLS-encrypted connection
struct TLS {
  ssl : SSL
  host : String?
  read_end : Endpoint
  write_end : Endpoint
}

///|
pub suberror OpenSSLError String derive(Show)

///|
pub suberror ConnectionClosed derive(Show)

///|
fn[R : @io.Reader, W : @io.Writer] TLS::from_pair(
  ctx : SSL_CTX,
  r : R,
  w : W,
  host~ : String?,
) -> TLS {
  let read_end = Endpoint::new_read(r)
  let write_end = Endpoint::new_write(w)
  let rbio = create_bio(read_end)
  let wbio = create_bio(write_end)
  let ssl = SSL::new(ctx, rbio, wbio)
  { ssl, host, read_end, write_end }
}

///|
async fn TLS::handle_error(self : TLS, err : Int) -> Unit {
  match err {
    SSL_ERROR_WANT_READ => self.read_end.wait()
    SSL_ERROR_WANT_WRITE => self.write_end.wait()
    SSL_ERROR_SSL | SSL_ERROR_SYSCALL => raise OpenSSLError(err_get_error())
    SSL_ERROR_ZERO_RETURN => raise ConnectionClosed
    err => abort("unexpected error code \{err} from OpenSSL")
  }
}

///|
/// Create a TLS client that read from `r` and write to `w`.
/// `client_from_pair` will block until TLS handshake to remote server completed.
///
/// If `verify` is `true` (`true` by default),
/// `client_from_pair` will perform verification on server's certificate,
/// using the default verification setting of the OpenSSL library.
///
/// If `host` is present, it will be used to verify the peer's certificate.
///
/// If `host` is present and `sni` is `true` (`true` by default),
/// Server Name Indication (SNI) field of TLS will be set to `host`.
pub async fn[R : @io.Reader, W : @io.Writer] TLS::client_from_pair(
  r : R,
  w : W,
  verify? : Bool = true,
  host? : String,
  sni? : Bool = true,
) -> TLS {
  let self = TLS::from_pair(client_ctx, r, w, host~)
  if not(verify) {
    self.ssl.set_verify(false)
  }
  if host is Some(host) {
    let host = @encoding/utf8.encode(host)
    guard self.ssl.set_host(host) > 0 else {
      self.close()
      raise OpenSSLError(err_get_error())
    }
    if sni {
      guard self.ssl.set_sni(host) > 0 else {
        self.close()
        raise OpenSSLError(err_get_error())
      }
    }
  }
  while self.ssl.connect() is ret && ret <= 0 {
    self.handle_error(self.ssl.get_error(ret)) catch {
      err => {
        self.close()
        raise err
      }
    }
  }
  self
}

///|
/// Create a TLS client that read from write to `inner`.
/// `client` will block until TLS handshake to remote server completed.
///
/// If `verify` is `true` (`true` by default),
/// `client` will perform verification on server's certificate,
/// using the default verification setting of the OpenSSL library.
///
/// If `host` is present, it will be used to verify the peer's certificate.
///
/// If `host` is present and `sni` is `true` (`true` by default),
/// Server Name Indication (SNI) field of TLS will be set to `host`.
pub async fn[Inner : @io.Reader + @io.Writer] TLS::client(
  inner : Inner,
  verify? : Bool = true,
  host? : String,
  sni? : Bool = true,
) -> TLS {
  TLS::client_from_pair(inner, inner, verify~, host?, sni~)
}

///|
/// WARNING: this API is currently for testing only,
/// it may block the whole thread while reading certificate,
/// and may break any time in the future. DO NOT USE.
///
/// Create a TLS server connection that read from `r` and write to `w`.
/// `server_from_pair` will block until TLS handshake with client completed.
///
/// `private_key_file`, `private_key_type` specifies the private key of the server.
/// `certificate_file` and `certificate_type` specifies the certificate of the server.
pub async fn[R : @io.Reader, W : @io.Writer] TLS::server_from_pair(
  r : R,
  w : W,
  private_key_file~ : Bytes,
  private_key_type~ : X509FileType,
  certificate_file~ : Bytes,
  certificate_type~ : X509FileType,
) -> TLS {
  let self = TLS::from_pair(server_ctx, r, w, host=None)
  if self.ssl.use_certificate_file(certificate_file, certificate_type) != 1 {
    self.close()
    raise OpenSSLError(err_get_error())
  }
  if self.ssl.use_private_key_file(private_key_file, private_key_type) != 1 {
    self.close()
    raise OpenSSLError(err_get_error())
  }
  while self.ssl.accept() is ret && ret <= 0 {
    self.handle_error(self.ssl.get_error(ret)) catch {
      err => {
        self.close()
        raise err
      }
    }
  }
  self
}

///|
/// WARNING: this API is currently for testing only,
/// it may block the whole thread while reading certificate,
/// and may break any time in the future. DO NOT USE.
///
/// Create a TLS server connection that read from and write to `inner`.
/// `server` will block until TLS handshake with client completed.
///
/// `private_key_file`, `private_key_type` specifies the private key of the server.
/// `certificate_file` and `certificate_type` specifies the certificate of the server.
pub async fn[Inner : @io.Reader + @io.Writer] TLS::server(
  inner : Inner,
  private_key_file~ : Bytes,
  private_key_type~ : X509FileType,
  certificate_file~ : Bytes,
  certificate_type~ : X509FileType,
) -> TLS {
  TLS::server_from_pair(
    inner,
    inner,
    private_key_file~,
    private_key_type~,
    certificate_file~,
    certificate_type~,
  )
}

///|
pub impl @io.Reader for TLS with read(
  self,
  buf,
  offset? : Int = 0,
  max_len? : Int = buf.length() - offset,
) {
  while self.ssl.read(buf, offset, max_len) is ret {
    if ret > 0 {
      return ret
    }
    let err = self.ssl.get_error(ret)
    if err is SSL_ERROR_ZERO_RETURN {
      return 0
    }
    self.handle_error(err)
  } else {
    // imposible
    0
  }
}

///|
pub impl @io.Writer for TLS with write_once(self, buf, offset~, len~) {
  while self.ssl.write(buf, offset, len) is ret {
    if ret > 0 {
      return ret
    }
    self.handle_error(self.ssl.get_error(ret))
  } else {
    // imposible
    0
  }
}

///|
/// Close a TLS connection and release related resource.
/// THIS FUNCTION MUST BE CALLED BEFORE CLOSING UNDERLYING TRANSPORT!!!
///
/// Note that this function will not perform the TLS shutdown process,
/// for graceful shutdown of a TLS connection, see `TLS::shutdown`.
pub fn TLS::close(self : TLS) -> Unit {
  self.read_end.close()
  self.write_end.close()
  self.ssl.free()
  // We must make sure the host string lives longer than `self.ssl`
  ignore(self.host)
}

///|
/// Shutdown a TLS connection gracefully.
/// This function MUST be called before `close`,
/// and MUST NOT be called if the TLS connection fail with other error.
///
/// Note that the main purpose of TLS shutdown is to ensure integrity
/// before closing the underlying transport.
/// So if your application protocol has its own way of ensuring integrity
/// (e.g. `Content-Length` in HTTP/1.1),
/// it is not necessary to call `shutdown`.
///
/// Shutting down a TLS connection involves communicating with remote peer,
/// which may die unexpectedly or become irresponsive.
/// Furthermore, some servers may not response correctly to TLS shutdown.
/// So it is highly recommended to add a timeout when calling this function,
/// to prevent the program from haning indefinitely.
pub async fn TLS::shutdown(self : TLS) -> Unit {
  while self.ssl.shutdown() is ret && ret <= 0 {
    let err = if ret == 0 {
      SSL_ERROR_WANT_READ
    } else {
      self.ssl.get_error(ret)
    }
    match err {
      SSL_ERROR_WANT_READ if self.read_end.state is Closed => break
      SSL_ERROR_WANT_WRITE if self.write_end.state is Closed => break
      _ => self.handle_error(err)
    }
  }
}
