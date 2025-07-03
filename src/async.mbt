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
let curr_loop : Ref[@event_loop.EventLoop?] = @ref.new(None)

///|
pub fn with_event_loop(f : async () -> Unit raise) -> Unit raise {
  guard curr_loop.val is None
  let evloop = @event_loop.EventLoop::new()
  curr_loop.val = Some(evloop)
  let _ = @coroutine.spawn(f)
  evloop.run_forever()
  curr_loop.val = None
}

///|
pub async fn wait_fd(fd : Int) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  evloop.wait_for_fd(fd, oneshot=false, events=Read)
}

///|
pub async fn sleep(ms : Int) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  evloop.sleep(ms)
}
