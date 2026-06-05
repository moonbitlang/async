///|
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
extern "C" fn init_env() = "init_env"

///|
extern "C" fn free_env() = "free_env"

///|
#cfg(platform="windows")
#borrow(out)
extern "C" fn next_entry_fill(
  out : String,
  out_len : Int,
) -> Int = "next_entry_fill"

///|
#cfg(platform="windows")
fn next_entry() -> String {
  let buffer_len = 32768
  let buffer = String::make(buffer_len, '\u{0}')
  let actual_len = next_entry_fill(buffer, buffer_len)
  if 0 < actual_len && actual_len <= buffer_len {
    buffer[:actual_len].to_owned()
  } else if actual_len > buffer_len {
    let result = String::make(actual_len, '\u{0}')
    if next_entry_fill(result, actual_len) == actual_len {
      result
    } else {
      ""
    }
  } else {
    ""
  }
}

///|
#cfg(platform="windows")
fn main {
  init_env()
  defer free_env()
  while next_entry() is entry && entry.length() > 0 {
    println(entry)
  }
}

///|
#cfg(not(platform="windows"))
#borrow(out)
extern "C" fn next_entry_fill(
  out : Bytes,
  out_len : Int,
) -> Int = "next_entry_fill"

///|
#cfg(not(platform="windows"))
fn next_entry() -> Bytes {
  let buffer_len = 32768
  let buffer = Bytes::make(buffer_len, 0)
  let actual_len = next_entry_fill(buffer, buffer_len)
  if 0 < actual_len && actual_len <= buffer_len {
    buffer[:actual_len].to_owned()
  } else if actual_len > buffer_len {
    let result = Bytes::make(actual_len, 0)
    if next_entry_fill(result, actual_len) == actual_len {
      result
    } else {
      b""
    }
  } else {
    b""
  }
}

///|
#cfg(not(platform="windows"))
fn main {
  init_env()
  defer free_env()
  while next_entry() is entry && entry.length() > 0 {
    println(@utf8.decode_lossy(entry))
  }
}
