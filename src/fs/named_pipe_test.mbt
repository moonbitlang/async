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
#cfg(not(platform="windows"))
#borrow(path)
extern "C" fn mkfifo(path : @os_string.OsString, mode : Int) -> Int = "mkfifo"

///|
#cfg(not(platform="windows"))
async test "cancel FIFO open" {
  @async.with_task_group(group => {
    let path = "_build/cancel_fifo_read"
    if mkfifo(@os_string.encode(path), 0o644) < 0 {
      @os_error.check_errno("mkfifo")
    }
    group.add_defer(() => @fs.remove(path))
    let result = @async.with_timeout_opt(500, () => @fs.open(
      path,
      mode=ReadOnly,
    ).close())
    inspect(result, content="None")
  })
}

///|
#cfg(platform="windows")
async test "cancel named pipe open" {
  let context = "cancel named pipe open test"
  let path = "\\\\.\\pipe\\moonbitlang_async_cancel_open_test"
  let server = @fd_util.create_named_pipe_server(
    @os_string.encode(path),
    is_async=false,
  )
  if !@fd_util.fd_is_valid(server) {
    @os_error.check_errno(context)
  }
  defer (try! @fd_util.close(server, kind=Pipe, context~))
  let client1 = @fs.open(path, mode=WriteOnly)
  defer client1.close()
  let result = @async.with_timeout_opt(500, () => @fs.open(path, mode=WriteOnly).close())
  inspect(result, content="None")
}
