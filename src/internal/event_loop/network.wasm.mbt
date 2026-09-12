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
#unsafe_skip_stub_check
fn gai_strerror(code : Int) -> @c_buffer.Buffer = "moonbitlang/async" "socket/gai_strerror"

///|
fn gai_error_to_string(code : Int) -> String {
  if platform is Windows {
    @os_error.errno_to_string(code)
  } else {
    let message = gai_strerror(code)
    defer message.free()
    @os_string.decode(message)
  }
}

///|
pub async fn IoHandle::recvfrom(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  @coroutine.check_cancellation()
  if platform is Windows {
    handle.recvfrom_windows(buf, offset~, len~, addr~, context~)
  } else {
    handle.recvfrom_unix(buf, offset~, len~, addr~, context~)
  }
}

///|
pub async fn IoHandle::sendto(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  @coroutine.check_cancellation()
  if platform is Windows {
    handle.sendto_windows(buf, offset~, len~, addr~, context~)
  } else {
    handle.sendto_unix(buf, offset~, len~, addr~, context~)
  }
}

///|
pub async fn IoHandle::connect(
  handle : IoHandle,
  addr : Bytes,
  context~ : String,
) -> Unit {
  @coroutine.check_cancellation()
  if platform is Windows {
    handle.connect_windows(addr, context~)
  } else {
    handle.connect_unix(addr, context~)
  }
}
