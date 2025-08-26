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
) -> TLS {
  let read_end = Endpoint::new_read(r)
  let write_end = Endpoint::new_write(w)
  let rbio = create_rbio(read_end, (bio, dst, len) => bio.read(dst, len))
  let wbio = create_wbio(write_end, (bio, src, len) => bio.write(src, len))
  let ssl = SSL::new(ctx, rbio, wbio)
  { ssl, read_end, write_end }
}

///|
async fn TLS::handle_error(self : TLS, err : Int) -> Unit raise {
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
/// If `sni` is present, its value will set the host name for the
/// Server Name Indication (SNI) field in ClientHello packet of TLS.
pub async fn[R : @io.Reader, W : @io.Writer] TLS::client_from_pair(
  r : R,
  w : W,
  verify~ : Bool = true,
  sni? : Bytes,
) -> TLS raise {
  let self = TLS::from_pair(client_ctx, r, w)
  if not(verify) {
    self.ssl.set_verify(false)
  }
  if sni is Some(host) {
    guard self.ssl.set_sni(host) > 0 else {
      self.close()
      raise OpenSSLError(err_get_error())
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
/// If `sni` is present, its value will set the host name for the
/// Server Name Indication (SNI) field in ClientHello packet of TLS.
pub async fn[Inner : @io.Reader + @io.Writer] TLS::client(
  inner : Inner,
  verify~ : Bool = true,
  sni? : Bytes,
) -> TLS raise {
  TLS::client_from_pair(inner, inner, verify~, sni?)
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
) -> TLS raise {
  let self = TLS::from_pair(server_ctx, r, w)
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
) -> TLS raise {
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
pub impl @io.Reader for TLS with read(self, buf, offset~, max_len~) {
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
pub async fn TLS::read(
  self : TLS,
  buf : FixedArray[Byte],
  offset~ : Int = 0,
  max_len~ : Int = buf.length() - offset,
) -> Int raise {
  @io.Reader::read(self, buf, offset~, max_len~)
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
}

///|
/// Shutdown a TLS connection gracefully.
/// This function MUST be called before `close`,
/// and MUST NOT be called if the TLS connection fail with other error.
///
/// Shutting down a TLS connection involves communicating with remote peer,
/// which may die unexpectedly or become irresponsive.
/// So it is highly recommended to add a timeout when calling this function,
/// to prevent the program from haning indefinitely.
pub async fn TLS::shutdown(self : TLS) -> Unit raise {
  while self.ssl.shutdown() is ret && ret <= 0 {
    if ret == 0 {
      self.read_end.wait()
    } else {
      self.handle_error(self.ssl.get_error(ret))
    }
  }
}
