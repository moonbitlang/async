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
#external
priv type SSL_CTX

///|
extern "C" fn SSL_CTX::is_null(self : SSL_CTX) -> Bool = "moonbitlang_async_tls_ssl_ctx_is_null"

///|
extern "C" fn SSL_CTX::client() -> SSL_CTX = "moonbitlang_async_tls_client_ctx"

///|
extern "C" fn SSL_CTX::server() -> SSL_CTX = "moonbitlang_async_tls_server_ctx"

///|
let client_ctx : SSL_CTX = {
  load_openssl()
  let ctx = SSL_CTX::client()
  guard not(ctx.is_null()) else {
    abort("failed to initialize SSL client context")
  }
  ctx
}

///|
let server_ctx : SSL_CTX = {
  load_openssl()
  let ctx = SSL_CTX::server()
  guard not(ctx.is_null()) else {
    abort("failed to initialize SSL server context")
  }
  ctx
}

///|
#external
priv type SSL

///|
extern "C" fn SSL::new(ctx : SSL_CTX, rbio : BIO, wbio : BIO) -> SSL = "moonbitlang_async_tls_ssl_new"

///|
extern "C" fn SSL::connect(self : SSL) -> Int = "moonbitlang_async_tls_ssl_connect"

///|
extern "C" fn SSL::set_verify(self : SSL, verify : Bool) = "moonbitlang_async_tls_ssl_set_verify"

///|
extern "C" fn SSL::accept(self : SSL) -> Int = "moonbitlang_async_tls_ssl_accept"

///|
pub(all) enum X509FileType {
  PEM = 1
  ANS1 = 2
}

///|
#borrow(file)
extern "C" fn SSL::use_certificate_file(
  self : SSL,
  file : Bytes,
  file_type : X509FileType,
) -> Int = "moonbitlang_async_tls_ssl_use_certificate_file"

///|
#borrow(file)
extern "C" fn SSL::use_private_key_file(
  self : SSL,
  file : Bytes,
  file_type : X509FileType,
) -> Int = "moonbitlang_async_tls_ssl_use_private_key_file"

///|
#borrow(buf)
extern "C" fn SSL::read(
  self : SSL,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
) -> Int = "moonbitlang_async_tls_ssl_read"

///|
#borrow(buf)
extern "C" fn SSL::write(
  self : SSL,
  buf : Bytes,
  offset : Int,
  len : Int,
) -> Int = "moonbitlang_async_tls_ssl_write"

///|
extern "C" fn SSL::shutdown(self : SSL) -> Int = "moonbitlang_async_tls_ssl_shutdown"

///|
extern "C" fn SSL::free(self : SSL) = "moonbitlang_async_tls_ssl_free"

///|
extern "C" fn SSL::get_error(self : SSL, ret : Int) -> Int = "moonbitlang_async_tls_ssl_get_error"

///|
const SSL_ERROR_SSL = 1

///|
const SSL_ERROR_WANT_READ = 2

///|
const SSL_ERROR_WANT_WRITE = 3

///|
const SSL_ERROR_SYSCALL = 5

///|
const SSL_ERROR_ZERO_RETURN = 6

///|
extern "C" fn err_get_error() -> String = "moonbitlang_async_tls_get_error"
