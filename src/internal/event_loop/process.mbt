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
#valtype
pub struct Process {
  pid : Int
  priv handle : IoHandle?
}

///|
pub fn Process::close(self : Process) -> Unit {
  if self.handle is Some(io) {
    io.close()
  }
}

///|
#cfg(target="native")
extern "C" fn open_pid_handle(pid : Int) -> @fd_util.Fd = "moonbitlang_async_open_pid_handle"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn open_pid_handle(pid : Int) -> @fd_util.Fd = "moonbitlang/async" "process/open_pid_handle"

///|
pub fn Process::from_pid(pid : Int, context~ : String) -> Process raise {
  let handle = open_pid_handle(pid)
  let handle = if !@fd_util.fd_is_valid(handle) {
    @os_error.check_errno(context)
    None
  } else {
    IoHandle::from_fd(
      handle,
      kind=Unknown,
      is_async=platform is Linux,
      read_only=true,
    )
    |> Some
  }
  { pid, handle }
}

///|
#cfg(target="native")
#borrow(out)
extern "C" fn get_process_result(
  handle : @fd_util.Fd,
  pid : Int,
  out : Ref[Int],
) -> Int = "moonbitlang_async_get_process_result"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
#borrow(out)
fn get_process_result(handle : @fd_util.Fd, pid : Int, out : Ref[Int]) -> Int = "moonbitlang/async" "process/get_process_result"
