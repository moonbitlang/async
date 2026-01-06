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
/// Opaque handle to a native C buffer.
///
/// `Buffer` represents a raw pointer managed by native code. All functions in
/// this package assume the pointer is valid and sized appropriately. It is an
/// internal FFI helper, not a general-purpose memory container.
///
/// # Example
/// ```mbt check
/// test {
///   let ptr : Buffer = null
///   inspect(Buffer::is_null(ptr), content="true")
/// }
/// ```
#external
pub type Buffer

///|
/// Copy bytes from a MoonBit `Bytes` into a C buffer.
///
/// `offset` and `len` select a range within `src`. The destination buffer must
/// have at least `len` bytes available.
///
/// # Safety
/// `dst` must be a valid writable buffer; `src` must be valid for the requested
/// range.
#borrow(src)
pub extern "C" fn Buffer::blit_from_bytes(
  dst : Buffer,
  src~ : Bytes,
  offset~ : Int,
  len~ : Int,
) = "moonbitlang_async_blit_to_c"

///|
/// Copy bytes from a C buffer into a MoonBit fixed array.
///
/// The destination array must have enough room for `len` bytes starting at
/// `offset`.
///
/// # Safety
/// `src` must be a valid readable buffer containing at least `len` bytes.
#borrow(dst)
pub extern "C" fn Buffer::blit_to_bytes(
  src : Buffer,
  dst~ : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) = "moonbitlang_async_blit_from_c"

///|
/// Read a single byte from the buffer at `index`.
///
/// # Safety
/// `buf` must be valid and the index must be within bounds of the allocated
/// buffer.
#borrow(buf)
#alias("_[_]")
pub extern "C" fn Buffer::get(buf : Buffer, index : Int) -> Byte = "moonbitlang_async_c_buffer_get"

///|
/// Measure the length of a NUL-terminated C string.
///
/// # Safety
/// `buf` must point to a valid NUL-terminated byte sequence.
pub extern "C" fn Buffer::strlen(buf : Buffer) -> Int = "moonbitlang_async_strlen"

///|
extern "C" fn Buffer::null() -> Buffer = "moonbitlang_async_null_pointer"

///|
/// A null C pointer for use with `Buffer`.
///
/// # Example
/// ```mbt check
/// test {
///   inspect(Buffer::is_null(null), content="true")
///   Buffer::free(null)
/// }
/// ```
pub let null : Buffer = Buffer::null()

///|
/// Check whether the pointer is null.
///
/// # Example
/// ```mbt check
/// test {
///   let ptr = null
///   inspect(Buffer::is_null(ptr), content="true")
/// }
/// ```
pub extern "C" fn Buffer::is_null(ptr : Buffer) -> Bool = "moonbitlang_async_pointer_is_null"

///|
/// Free a C buffer allocated with `malloc` or compatible APIs.
///
/// Passing `null` is allowed and has no effect.
pub extern "C" fn Buffer::free(buf : Buffer) = "free"
