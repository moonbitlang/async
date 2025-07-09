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
extern "C" fn pipe_ffi(out : FixedArray[Int]) -> Int = "moonbitlang_async_pipe"

///|
extern "C" fn get_blocking(fd : Int) -> Int = "moonbitlang_async_get_blocking"

///|
extern "C" fn set_nonblock(fd : Int) -> Int = "moonbitlang_async_set_nonblock"

///|
extern "C" fn set_blocking(fd : Int) -> Int = "moonbitlang_async_set_blocking"

///|
extern "C" fn read_ffi(
  fd : Int,
  buf : FixedArray[Byte],
  offset : Int,
  max_len : Int,
) -> Int = "moonbitlang_async_read"

///|
extern "C" fn write_ffi(
  fd : Int,
  buf : Bytes,
  offset : Int,
  max_len : Int,
) -> Int = "moonbitlang_async_write"
