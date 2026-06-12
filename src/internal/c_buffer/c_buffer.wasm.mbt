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
fn blit_to_c(dst : Buffer, src : Int, offset : Int, len : Int) -> Unit = "moonbit_v0" "c_buffer/blit_to_c"

///|
fn blit_from_c(src : Buffer, dst : Int, offset : Int, len : Int) -> Unit = "moonbit_v0" "c_buffer/blit_from_c"

///|
fn c_buffer_get(buf : Buffer, index : Int) -> Byte = "moonbit_v0" "c_buffer/c_buffer_get"

///|
fn strlen(buf : Buffer) -> Int = "moonbit_v0" "c_buffer/strlen"

///|
fn pointer_is_null(ptr : Buffer) -> Bool = "moonbit_v0" "c_buffer/pointer_is_null"

///|
fn buffer_to_ptr(buf : Buffer) -> Int =
  #|(func (param i32) (result i32) local.get 0)

///|
pub fn Buffer::to_ptr(buf : Buffer) -> Int {
  buffer_to_ptr(buf)
}

///|
#borrow(src)
pub fn Buffer::blit_from_bytes(
  dst : Buffer,
  src~ : Bytes,
  offset~ : Int,
  len~ : Int,
) -> Unit {
  blit_to_c(dst, @wasm_ffi.bytes_to_ptr(src), offset, len)
}

///|
#borrow(dst)
pub fn Buffer::blit_to_bytes(
  src : Buffer,
  dst~ : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) -> Unit {
  blit_from_c(src, @wasm_ffi.byte_array_to_ptr(dst), offset, len)
}

///|
#borrow(buf)
#alias("_[_]")
pub fn Buffer::get(buf : Buffer, index : Int) -> Byte {
  c_buffer_get(buf, index)
}

///|
pub fn Buffer::strlen(buf : Buffer) -> Int {
  strlen(buf)
}

///|
pub fn Buffer::is_null(ptr : Buffer) -> Bool {
  pointer_is_null(ptr)
}

///|
pub fn Buffer::free(buf : Buffer) -> Unit {
  if !buf.is_null() {
    @wasm_ffi.free(buf.to_ptr())
  }
}
