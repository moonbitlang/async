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
pub extern "wasm" fn free(position : Int) =
  #|(func (param i32) local.get 0 call $moonbit.decref)

///| Borrow a pointer to a Bytes object. The caller must keep the Bytes value live

///|
/// until the host import using the pointer has returned.
#borrow(bytes)
pub extern "wasm" fn bytes_to_ptr(bytes : Bytes) -> Int =
  #|(func (param i32) (result i32) local.get 0)

///| Take ownership of a Bytes pointer. The returned pointer must be released with

///|
/// `free` after the host import using it has returned.
#owned(bytes)
pub extern "wasm" fn bytes_to_owned_ptr(bytes : Bytes) -> Int =
  #|(func (param i32) (result i32) local.get 0)

///|
/// Borrow a pointer to a String object. The pointer addresses UTF-16 code
/// units, and the caller must keep the String value live until the host import
/// using the pointer has returned.
#borrow(str)
pub extern "wasm" fn string_to_ptr(str : String) -> Int =
  #|(func (param i32) (result i32) local.get 0)

///| Borrow a pointer to a byte array. The caller must keep the array live until

///|
/// the host import using the pointer has returned.
#borrow(bytes)
pub extern "wasm" fn byte_array_to_ptr(bytes : FixedArray[Byte]) -> Int =
  #|(func (param i32) (result i32) local.get 0)

///| Take ownership of a byte array pointer. The returned pointer must be released

///|
/// with `free` after the host import using it has returned.
#owned(bytes)
pub extern "wasm" fn byte_array_to_owned_ptr(bytes : FixedArray[Byte]) -> Int =
  #|(func (param i32) (result i32) local.get 0)
