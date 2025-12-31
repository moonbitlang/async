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
#cfg(not(platform="windows"))
#external
priv type SSL_CTX

///|
#cfg(not(platform="windows"))
extern "C" fn SSL_CTX::is_null(self : SSL_CTX) -> Bool = "moonbitlang_async_tls_ssl_ctx_is_null"

///|
#cfg(not(platform="windows"))
extern "C" fn SSL_CTX::client() -> SSL_CTX = "moonbitlang_async_tls_client_ctx"

///|
#cfg(not(platform="windows"))
extern "C" fn SSL_CTX::server() -> SSL_CTX = "moonbitlang_async_tls_server_ctx"

///|
#cfg(not(platform="windows"))
let client_ctx : SSL_CTX = {
  load_openssl()
  let ctx = SSL_CTX::client()
  guard not(ctx.is_null()) else {
    abort("failed to initialize SSL client context")
  }
  ctx
}

///|
#cfg(not(platform="windows"))
let server_ctx : SSL_CTX = {
  load_openssl()
  let ctx = SSL_CTX::server()
  guard not(ctx.is_null()) else {
    abort("failed to initialize SSL server context")
  }
  ctx
}

///|
#cfg(not(platform="windows"))
#external
priv type SSL

///|
#cfg(not(platform="windows"))
extern "C" fn SSL::new(ctx : SSL_CTX, rbio : BIO, wbio : BIO) -> SSL = "moonbitlang_async_tls_ssl_new"

///|
#cfg(not(platform="windows"))
extern "C" fn SSL::connect(self : SSL) -> Int = "moonbitlang_async_tls_ssl_connect"

///|
#cfg(not(platform="windows"))
#borrow(host)
extern "C" fn SSL::set_host(self : SSL, host : Bytes) -> Int = "moonbitlang_async_tls_ssl_set_host"

///|
#cfg(not(platform="windows"))
#borrow(host)
extern "C" fn SSL::set_sni(self : SSL, host : Bytes) -> Int = "moonbitlang_async_tls_ssl_set_sni"

///|
#cfg(not(platform="windows"))
extern "C" fn SSL::set_verify(self : SSL, verify : Bool) = "moonbitlang_async_tls_ssl_set_verify"

///|
#cfg(not(platform="windows"))
extern "C" fn SSL::accept(self : SSL) -> Int = "moonbitlang_async_tls_ssl_accept"

///|
pub(all) enum X509FileType {
  PEM = 1
  ANS1 = 2
}

///|
#cfg(not(platform="windows"))
#borrow(file)
extern "C" fn SSL::use_certificate_file(
  self : SSL,
  file : Bytes,
  file_type : X509FileType,
) -> Int = "moonbitlang_async_tls_ssl_use_certificate_file"

///|
#cfg(not(platform="windows"))
#borrow(file)
extern "C" fn SSL::use_private_key_file(
  self : SSL,
  file : Bytes,
  file_type : X509FileType,
) -> Int = "moonbitlang_async_tls_ssl_use_private_key_file"

///|
#cfg(not(platform="windows"))
#borrow(buf)
extern "C" fn SSL::read(
  self : SSL,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
) -> Int = "moonbitlang_async_tls_ssl_read"

///|
#cfg(not(platform="windows"))
#borrow(buf)
extern "C" fn SSL::write(
  self : SSL,
  buf : Bytes,
  offset : Int,
  len : Int,
) -> Int = "moonbitlang_async_tls_ssl_write"

///|
#cfg(not(platform="windows"))
extern "C" fn SSL::shutdown(self : SSL) -> Int = "moonbitlang_async_tls_ssl_shutdown"

///|
#cfg(not(platform="windows"))
extern "C" fn SSL::free(self : SSL) = "moonbitlang_async_tls_ssl_free"

///|
#cfg(not(platform="windows"))
extern "C" fn SSL::get_error(self : SSL, ret : Int) -> Int = "moonbitlang_async_tls_ssl_get_error"

///|
#cfg(not(platform="windows"))
const SSL_ERROR_SSL = 1

///|
#cfg(not(platform="windows"))
const SSL_ERROR_WANT_READ = 2

///|
#cfg(not(platform="windows"))
const SSL_ERROR_WANT_WRITE = 3

///|
#cfg(not(platform="windows"))
const SSL_ERROR_SYSCALL = 5

///|
#cfg(not(platform="windows"))
const SSL_ERROR_ZERO_RETURN = 6

///|
#cfg(not(platform="windows"))
#borrow(buf)
extern "C" fn err_get_error_ffi(buf : Bytes) -> Int = "moonbitlang_async_tls_get_error"

///|
#cfg(not(platform="windows"))
fn err_get_error() -> String {
  let buf = Bytes::make(256, 0)
  let len = err_get_error_ffi(buf)
  @bytes_util.ascii_to_string(buf[:len])
}

///|
#cfg(not(platform="windows"))
#borrow(buf)
extern "C" fn rand_bytes_ffi(buf : FixedArray[Byte], num : Int) -> Int = "moonbitlang_async_tls_rand_bytes"

///|
/// Generate cryptographically secure random bytes using OpenSSL's RAND_bytes
/// Returns 1 on success, 0 on failure
#cfg(not(platform="windows"))
#internal(internal, "for internal use only")
pub fn rand_bytes(num : Int) -> Bytes raise {
  let result = FixedArray::make(num, b'\x00')
  if rand_bytes_ffi(result, num) != 1 {
    raise Failure(err_get_error())
  }
  result.unsafe_reinterpret_as_bytes()
}

///|
#cfg(not(platform="windows"))
#borrow(src, dst)
extern "C" fn sha1_ffi(src : Bytes, len : Int, dst : FixedArray[Byte]) = "moonbitlang_async_tls_SHA1"

///|
#cfg(not(platform="windows"))
#internal(internal, "for internal use only")
pub fn sha1(src : Bytes) -> Bytes {
  let result = FixedArray::make(20, b'\x00')
  sha1_ffi(src, src.length(), result)
  result.unsafe_reinterpret_as_bytes()
}
