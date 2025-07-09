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
priv struct EventLoop {
  poll : Instance
  tasks : Map[Int, Task]
  timers : @sorted_set.T[Timer]
}

///|
priv struct Task {
  mut events : Events
  mut read : @coroutine.Coroutine?
  mut write : Set[@coroutine.Coroutine]
}

///|
let curr_loop : Ref[EventLoop?] = @ref.new(None)

///|
pub fn with_event_loop(f : async () -> Unit raise) -> Unit raise {
  guard curr_loop.val is None
  let evloop = { poll: Instance::new(), tasks: {}, timers: @sorted_set.new() }
  curr_loop.val = Some(evloop)
  let main = @coroutine.spawn(f)
  evloop.run_forever()
  curr_loop.val = None
  main.unwrap()
}

///|
fn EventLoop::run_forever(self : Self) -> Unit raise {
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
      match (events, task.events) {
        (Read, ReadWrite) => self.poll.modify(fd, events=Write)
        (Write, ReadWrite) => self.poll.modify(fd, events=Read)
        (_, original_events) => {
          self.tasks.remove(fd)
          self.poll.remove(fd, events=original_events)
        }
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
pub async fn wait_fd_read(fd : Int) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  let task = match evloop.tasks.get(fd) {
    None => {
      let task = { read: None, write: Set::new(), events: Read }
      evloop.tasks[fd] = task
      task
    }
    Some(task) => task
  }
  guard task.read is None
  task.read = Some(@coroutine.current_coroutine())
  if task.write.is_empty() {
    task.events = Read
    evloop.poll.register(fd, events=Read, oneshot=false)
  } else {
    task.events = ReadWrite
    evloop.poll.modify(fd, events=ReadWrite, oneshot=false)
  }
  ignore(@coroutine.suspend()) catch {
    err => {
      task.read = None
      if task.write.is_empty() {
        evloop.tasks.remove(fd)
        evloop.poll.remove(fd, events=Read)
      } else {
        task.events = Write
        evloop.poll.modify(fd, events=Write)
      }
      raise err
    }
  }
}

///|
pub async fn wait_fd_write(fd : Int) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  let task = match evloop.tasks.get(fd) {
    None => {
      let task = { read: None, write: Set::new(), events: Write }
      evloop.tasks[fd] = task
      task
    }
    Some(task) => task
  }
  if task.write.is_empty() {
    if task.read is None {
      task.events = Write
      evloop.poll.register(fd, events=Write, oneshot=false)
    } else {
      task.events = ReadWrite
      evloop.poll.modify(fd, events=ReadWrite, oneshot=false)
    }
  }
  let coro = @coroutine.current_coroutine()
  task.write.add(coro)
  ignore(@coroutine.suspend()) catch {
    err => {
      task.write.remove(coro)
      if task.write.is_empty() {
        if task.read is None {
          evloop.tasks.remove(fd)
          evloop.poll.remove(fd, events=Write)
        } else {
          task.events = Read
          evloop.poll.modify(fd, events=Read)
        }
      }
      raise err
    }
  }
}

///|
pub fn close_fd(fd : Int) -> Unit {
  guard curr_loop.val is Some(evloop)
  if evloop.tasks.get(fd) is Some(task) {
    evloop.tasks.remove(fd)
    evloop.poll.remove(fd, events=task.events) catch {
      err => abort("detach \{fd} from loop: \{err}")
    }
  }
  close_ffi(fd)
}

///|
extern "C" fn close_ffi(fd : Int) = "close"

///|
fn EventLoop::flush_timer(self : EventLoop) -> Unit {
  while self.timers.iter().head() is Some(timer) &&
        timer.expire_time <= @time.ms_since_epoch() {
    self.timers.remove(timer)
    timer.coro.wake()
  }
}

///|
pub async fn sleep(duration : Int) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  let timer = Timer::new(duration, @coroutine.current_coroutine())
  evloop.timers.add(timer)
  @coroutine.suspend() catch {
    err => {
      evloop.timers.remove(timer)
      raise err
    }
  }
}
