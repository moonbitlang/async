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
pub fn Tty::input_fd(self : Tty) -> @fd_util.Fd {
  self.input.fd()
}

///|
/// Wait for input or a resize, then read input.
/// Return `-1` for a resize, which may be reported after later input.
/// With `block_resize`, like a blocked signal, a resize does not end the wait
/// and stays pending until a read without `block_resize`.
pub async fn Tty::read(
  self : Tty,
  buf : FixedArray[Byte],
  offset~ : Int32,
  len~ : Int32,
  raw~ : Bool,
  block_resize~ : Bool,
  context~ : String,
) -> Int32 {
  @coroutine.check_cancellation()
  guard! curr_loop.val is Some(evloop)
  for ;; {
    if evloop.resize.pending && !block_resize {
      evloop.resize.pending = false
      return -1
    }
    let n = self.read_input(buf, offset~, len~, raw~, block_resize~, context~)
    guard n < 0 else { return n }
    evloop.resize.pending = true
  }
}
