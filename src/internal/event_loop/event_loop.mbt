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
  tasks : Map[Int, Task]
}

///|
priv struct Task {
  mut callback : Option[() -> Unit]
  oneshot : Bool
}

///|
pub fn EventLoop::new() -> EventLoop {
  { poll: Instance::new(), tasks: {} }
}

///|
pub fn EventLoop::run_forever(self : Self) -> Unit raise {
  while not(self.tasks.is_empty()) {
    let n = self.poll.wait(timeout=-1)
    if n < 0 {
      @os_error.check_errno()
    }
    for i in 0..<n {
      let event = get_event(i)
      let fd = event.fd()
      let task = self.tasks.get(fd).unwrap()
      if task.callback is Some(cb) {
        if task.oneshot {
          task.callback = None
        }
        cb()
      }
    }
  }
  self.poll.destroy()
}

///|
pub fn EventLoop::register(
  self : EventLoop,
  fd : Int,
  cb : () -> Unit,
  oneshot~ : Bool,
  events~ : Events
) -> Unit raise @os_error.OSError {
  match self.tasks.get(fd) {
    None => {
      self.tasks[fd] = { callback: Some(cb), oneshot }
      if 0 != self.poll.register(fd, events~, oneshot~) {
        @os_error.check_errno()
      }
    }
    Some(task) => {
      guard task.callback is None else {
        abort("file descriptor \{fd} already subscribed")
      }
      task.callback = Some(cb)
      if 0 != self.poll.modify(fd, events~, oneshot~) {
        @os_error.check_errno()
      }
    }
  }
}

///|
pub fn EventLoop::unregister(self : EventLoop, fd : Int) -> Unit {
  let task = self.tasks.get(fd).unwrap()
  task.callback = None
  let _ = self.poll.remove(fd)
}

///|
pub fn EventLoop::close(self : EventLoop, fd : Int) -> Unit {
  self.tasks.remove(fd)
  close(fd)
}

///|
extern "C" fn close(fd : Int) = "close"
