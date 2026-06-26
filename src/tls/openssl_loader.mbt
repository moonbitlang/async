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
#borrow(major, minor, fix)
extern "C" fn load_openssl_ffi(
  major : Ref[Int],
  minor : Ref[Int],
  fix : Ref[Int],
) -> Int = "moonbitlang_async_load_openssl"

///|
#cfg(not(platform="windows"))
extern "C" fn init_bio_method(
  read : FuncRef[(BIO, @c_buffer.Buffer, Int) -> Int],
  write : FuncRef[(BIO, @c_buffer.Buffer, Int) -> Int],
) = "moonbitlang_async_init_bio_method"

///|
/// `None` until the first load attempt; afterwards caches the outcome so a
/// failed load fails fast on every subsequent call instead of retrying.
#cfg(not(platform="windows"))
let openssl_loaded : Ref[Result[Unit, Error]?] = Ref(None)

///|
/// Lazily load OpenSSL on first use, so a program that never touches TLS pays
/// nothing. Every raw-symbol FFI wrapper calls this first; all other FFI runs on
/// handles those produce, so it is transitively covered. The outcome is cached →
/// success makes repeat calls free, failure re-raises the same error immediately.
#cfg(not(platform="windows"))
fn load_openssl() -> Unit raise {
  match openssl_loaded.val {
    Some(Ok(_)) => return
    Some(Err(err)) => raise err
    None => ()
  }
  let result = try {
    load_openssl_unchecked()
    Ok(())
  } catch {
    err => Err(err)
  }
  openssl_loaded.val = Some(result)
  match result {
    Ok(_) => ()
    Err(err) => raise err
  }
}

///|
#cfg(not(platform="windows"))
fn load_openssl_unchecked() -> Unit raise {
  let major = Ref(0)
  let minor = Ref(0)
  let fix = Ref(0)
  match load_openssl_ffi(major, minor, fix) {
    0 => ()
    1 => raise TlsError("failed to load OpenSSL")
    2 => raise TlsError("failed to get OpenSSL version")
    3 =>
      raise TlsError(
        "unsupported OpenSSL version \{major.val}.\{minor.val}.\{fix.val}",
      )
    4 => raise TlsError("failed to load some OpenSSL function")
    _ => panic()
  }
  init_bio_method((bio, dst, len) => bio.read(dst, len)) <| ((bio, src, len) => {
    bio.write(src, len)
  })
}
