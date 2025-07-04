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
  timers : @sorted_set.T[Timer]
}

///|
priv struct Task {
  mut read : @coroutine.Coroutine?
  mut write : Set[@coroutine.Coroutine]
}

///|
pub fn EventLoop::new() -> EventLoop {
  { poll: Instance::new(), tasks: {}, timers: @sorted_set.new() }
}

///|
pub fn EventLoop::run_forever(self : Self) -> Unit raise {
  while not(self.tasks.is_empty() && self.timers.is_empty()) {
    let timeout = match self.timers.iter().head() {
      Some(timer) =>
        @cmp.maximum(0, (timer.expire_time - @time.ms_since_epoch()).to_int())
      None => -1
    }
    let n = self.poll.wait(timeout~)
    if n < 0 {
      @os_error.check_errno()
    }
    self.flush_timer()
    let coros = []
    for i in 0..<n {
      let event = get_event(i)
      let fd = event.fd()
      guard self.tasks.get(fd) is Some(task)
      let events = event.events()
      if events is Read && not(task.write.is_empty()) {
        self.poll.modify(fd, events=Write)
      }
      if events is Write && task.read is None {
        self.poll.modify(fd, events=Read)
      } else {
        self.tasks.remove(fd)
        self.poll.remove(fd)
      }
      if task.read is Some(coro) && not(events is Write) {
        task.read = None
        coros.push(coro)
      }
      if not(task.write.is_empty() || events is Read) {
        for coro in task.write {
          coros.push(coro)
        }
        task.write = Set::new()
      }
    }
    for coro in coros {
      coro.wake()
      self.flush_timer()
    }
  }
  self.poll.destroy()
}

///|
pub async fn EventLoop::wait_for_fd_read(
  self : EventLoop,
  fd : Int
) -> Unit raise {
  let task = match self.tasks.get(fd) {
    None => {
      let task = { read: None, write: Set::new() }
      self.tasks[fd] = task
      task
    }
    Some(task) => task
  }
  guard task.read is None
  task.read = Some(@coroutine.current_coroutine())
  if task.write.is_empty() {
    self.poll.register(fd, events=Read, oneshot=false)
  } else {
    self.poll.modify(fd, events=ReadWrite, oneshot=false)
  }
  ignore(@coroutine.suspend()) catch {
    err => {
      task.read = None
      if task.write.is_empty() {
        self.tasks.remove(fd)
        self.poll.remove(fd)
      } else {
        self.poll.modify(fd, events=Write)
      }
      raise err
    }
  }
}

///|
pub async fn EventLoop::wait_for_fd_write(
  self : EventLoop,
  fd : Int
) -> Unit raise {
  let task = match self.tasks.get(fd) {
    None => {
      let task = { read: None, write: Set::new() }
      self.tasks[fd] = task
      task
    }
    Some(task) => task
  }
  if task.write.is_empty() {
    if task.read is None {
      self.poll.register(fd, events=Write, oneshot=false)
    } else {
      self.poll.modify(fd, events=ReadWrite, oneshot=false)
    }
  }
  let coro = @coroutine.current_coroutine()
  task.write.add(coro)
  ignore(@coroutine.suspend()) catch {
    err => {
      task.write.remove(coro)
      if task.write.is_empty() {
        if task.read is None {
          self.tasks.remove(fd)
          self.poll.remove(fd)
        } else {
          self.poll.modify(fd, events=Read)
        }
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

///|
fn EventLoop::flush_timer(self : EventLoop) -> Unit {
  while self.timers.iter().head() is Some(timer) &&
        timer.expire_time <= @time.ms_since_epoch() {
    self.timers.remove(timer)
    timer.coro.wake()
  }
}

///|
pub async fn EventLoop::sleep(self : EventLoop, duration : Int) -> Unit raise {
  let timer = Timer::new(duration, @coroutine.current_coroutine())
  self.timers.add(timer)
  ignore(@coroutine.suspend()) catch {
    err => {
      self.timers.remove(timer)
      raise err
    }
  }
}
