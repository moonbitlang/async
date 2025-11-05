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
fn setup_stdio(
  fd : Int,
  context~ : String,
  restore_context~ : String,
) -> IOHandle {
  let kind = @fd_util.fstat_sync(fd, context~).kind() catch {
    err => abort("\{context}: \{err}")
  }
  let handle = { fd, kind, events: NoEvent, read: None, write: None }
  let need_unblock = kind.can_poll() &&
    not(try! @fd_util.fd_is_nonblocking(fd, context~))
  fn init() raise {
    guard curr_loop.val is Some(evloop)
    guard evloop.fds.get(fd) is None
    evloop.fds[fd] = handle
    if need_unblock {
      @fd_util.set_nonblocking(fd, context~)
    }
  }

  fn exit() raise {
    let _ = handle.detach_from_event_loop()
    handle.events = NoEvent
    if need_unblock {
      @fd_util.set_nonblocking(fd, context=restore_context)
    }
  }

  register_hook(init~, exit~)
  handle
}

///|
pub let stdin : IOHandle = setup_stdio(
  0,
  context="initialize `stdin`",
  restore_context="restore `stdin`",
)

///|
pub let stdout : IOHandle = setup_stdio(
  1,
  context="initialize `stdout`",
  restore_context="restore `stdout`",
)

///|
pub let stderr : IOHandle = setup_stdio(
  2,
  context="initialize `stderr`",
  restore_context="restore `stderr`",
)
