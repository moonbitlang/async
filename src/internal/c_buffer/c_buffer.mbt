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
pub type Buffer

///|
#borrow(src)
pub extern "C" fn Buffer::blit_from_bytes(
  dst : Buffer,
  src~ : Bytes,
  offset~ : Int,
  len~ : Int,
) = "moonbitlang_async_blit_to_c"

///|
#borrow(dst)
pub extern "C" fn Buffer::blit_to_bytes(
  src : Buffer,
  dst~ : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) = "moonbitlang_async_blit_from_c"

///|
#borrow(buf)
#alias("_[_]")
pub extern "C" fn Buffer::get(buf : Buffer, index : Int) -> Byte = "moonbitlang_async_c_buffer_get"

///|
pub extern "C" fn Buffer::strlen(buf : Buffer) -> Int = "moonbitlang_async_strlen"

///|
extern "C" fn Buffer::null() -> Buffer = "moonbitlang_async_null_pointer"

///|
pub let null : Buffer = Buffer::null()

///|
#borrow(buf)
pub extern "C" fn Buffer::is_null(buf : Buffer) -> Bool = "moonbitlang_async_is_null"

///|
pub extern "C" fn Buffer::free(buf : Buffer) = "free"

///|
fn[X, Y] unsafe_cast(x : X) -> Y = "%identity"

///|
/// Get a null C pointer.
/// WARNING: the result type MUST be a foreign pointer type declared with `#external`
pub fn[X] null_ptr() -> X {
  unsafe_cast(null)
}

///|
/// Check if a C pointer is null.
/// WARNING: the parameter MUST be a foreign pointer type declared with `#external`
pub fn[X] ptr_is_null(ptr : X) -> Bool {
  Buffer::is_null(unsafe_cast(ptr))
}
