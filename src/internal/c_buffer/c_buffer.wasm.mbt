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
struct Buffer(UInt64)

///|
#unsafe_skip_stub_check
fn Buffer::is_null_ffi(buf : Buffer) -> Bool = "moonbitlang/async" "c_buffer/is_null"

///|
#unsafe_skip_stub_check
#borrow(src)
pub fn Buffer::blit_from_bytes(
  dst : Buffer,
  dst_offset? : Int = 0,
  src~ : Bytes,
  src_offset? : Int = 0,
  len~ : Int,
) -> Unit = "moonbitlang/async" "c_buffer/blit_to_c"

///|
#unsafe_skip_stub_check
#borrow(dst)
pub fn Buffer::blit_to_bytes(
  src : Buffer,
  src_offset? : Int = 0,
  dst~ : FixedArray[Byte],
  dst_offset? : Int = 0,
  len~ : Int,
) -> Unit = "moonbitlang/async" "c_buffer/blit_from_c"

///|
#unsafe_skip_stub_check
#borrow(buf)
#alias("_[_]")
pub fn Buffer::get(buf : Buffer, index : Int) -> Byte = "moonbitlang/async" "c_buffer/c_buffer_get"

///|
#unsafe_skip_stub_check
pub fn Buffer::strlen(buf : Buffer) -> Int = "moonbitlang/async" "c_buffer/strlen"

///|
#unsafe_skip_stub_check
#as_free_fn
pub fn Buffer::new(size : Int) -> Buffer = "moonbitlang/async" "c_buffer/new"

///|
pub fn Buffer::is_null(buf : Buffer) -> Bool {
  buf.is_null_ffi()
}

///|
#unsafe_skip_stub_check
fn Buffer::free_ffi(buf : Buffer) -> Unit = "moonbitlang/async" "c_buffer/free"

///|
pub fn Buffer::free(buf : Buffer) -> Unit {
  if !buf.is_null() {
    buf.free_ffi()
  }
}
