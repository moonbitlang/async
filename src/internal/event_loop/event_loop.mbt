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
struct EventLoop {
  poll : Instance
  tasks : Map[Int, @coroutine.Coroutine]
}

///|
pub fn EventLoop::new() -> EventLoop {
  { poll: Instance::new(), tasks: {} }
}

///|
pub fn EventLoop::run_forever(self : Self) -> Unit raise {
  while not(self.tasks.is_empty()) {
    let n = self.poll.wait(timeout=5000)
    if n < 0 {
      @os_error.check_errno()
    }
    for i in 0..<n {
      let event = get_event(i)
      let fd = event.fd()
      guard self.tasks.get(fd) is Some(coro)
      self.tasks.remove(fd)
      if 0 != self.poll.remove(fd) {
        @os_error.check_errno()
      }
      coro.wake()
    }
  }
  self.poll.destroy()
}

///|
pub async fn EventLoop::wait_for_fd(
  self : EventLoop,
  fd : Int,
  oneshot~ : Bool,
  events~ : Events
) -> Unit raise {
  guard self.tasks.get(fd) is None
  if 0 != self.poll.register(fd, events~, oneshot~) {
    @os_error.check_errno()
  }
  self.tasks[fd] = @coroutine.current_coroutine()
  @coroutine.suspend() catch {
    err => {
      self.tasks.remove(fd)
      if 0 != self.poll.remove(fd) {
        @os_error.check_errno()
      }
      raise err
    }
  }
}

///|
pub fn EventLoop::close(self : EventLoop, fd : Int) -> Unit {
  self.tasks.remove(fd)
  close(fd)
}

///|
extern "C" fn close(fd : Int) = "close"
