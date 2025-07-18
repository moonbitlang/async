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
  jobs : Map[Int, JobHandle]
  job_completion_pipe : Int
}

///|
priv struct Task {
  mut events : Int
  mut read : @coroutine.Coroutine?
  mut write : Set[@coroutine.Coroutine]
}

///|
priv struct JobHandle {
  job : @thread_pool.Job
  coro : @coroutine.Coroutine
}

///|
let curr_loop : Ref[EventLoop?] = @ref.new(None)

///|
pub fn with_event_loop(f : async () -> Unit raise) -> Unit raise {
  guard curr_loop.val is None
  let job_completion_pipe = @thread_pool.init_thread_pool()
  let evloop = {
    poll: Instance::new(),
    tasks: {},
    jobs: {},
    job_completion_pipe,
  }
  evloop.poll.register(
    job_completion_pipe,
    prev_events=NoEvent,
    new_events=Read,
  )
  curr_loop.val = Some(evloop)
  let main = @coroutine.spawn(f)
  @coroutine.reschedule()
  evloop.run_forever()
  curr_loop.val = None
  evloop.poll.remove(job_completion_pipe, events=Read)
  evloop.poll.destroy()
  @thread_pool.destroy_thread_pool()
  main.unwrap()
}

///|
fn EventLoop::run_forever(self : Self) -> Unit raise {
  while not(@coroutine.no_more_work()) {
    let timeout = match @coroutine.next_expire_time() {
      Some(t) => @cmp.maximum(0, (t - @time.ms_since_epoch()).to_int())
      None => -1
    }
    let n = self.poll.wait(timeout~)
    if n < 0 {
      @os_error.check_errno()
    }
    @coroutine.reschedule()
    for i in 0..<n {
      let event = get_event(i)
      let fd = event.fd()
      if fd == self.job_completion_pipe {
        while @thread_pool.fetch_completion() is Some(job_id) {
          guard self.jobs.get(job_id) is Some({ job: _, coro })
          self.jobs.remove(job_id)
          coro.wake()
        }
        continue
      }
      guard self.tasks.get(fd) is Some(task)
      let events = event.events()
      if task.read is Some(coro) && (events & Read) != 0 {
        task.read = None
        coro.wake()
      }
      if (events & Write) != 0 {
        for coro in task.write {
          coro.wake()
        }
        task.write = Set::new()
      }
    }
    @coroutine.reschedule()
  }
  for fd, task in self.tasks {
    guard task.read is None && task.write.is_empty()
    self.poll.remove(fd, events=task.events) catch {
      err => abort("detach \{fd} from loop: \{err}")
    }
    close_ffi(fd)
  }
  self.tasks.clear()
}

///|
pub fn prepare_fd_read(fd : Int) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  let task = match evloop.tasks.get(fd) {
    None => {
      let task = { read: None, write: Set::new(), events: NoEvent }
      evloop.tasks[fd] = task
      task
    }
    Some(task) => task
  }
  guard task.read is None
  if (task.events & Read) == 0 {
    evloop.poll.register(
      fd,
      prev_events=task.events,
      new_events=Read,
      oneshot=false,
    )
    task.events = task.events | Read
  }
}

///|
pub async fn wait_fd_read(fd : Int) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  guard evloop.tasks.get(fd) is Some(task)
  guard (task.events & Read) != 0
  task.read = Some(@coroutine.current_coroutine())
  @coroutine.suspend() catch {
    err => {
      task.read = None
      raise err
    }
  }
}

///|
pub fn prepare_fd_write(fd : Int) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  let task = match evloop.tasks.get(fd) {
    None => {
      let task = { read: None, write: Set::new(), events: NoEvent }
      evloop.tasks[fd] = task
      task
    }
    Some(task) => task
  }
  if (task.events & Write) == 0 {
    evloop.poll.register(
      fd,
      prev_events=task.events,
      new_events=Write,
      oneshot=false,
    )
    task.events = task.events | Write
  }
}

///|
pub async fn wait_fd_write(fd : Int) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  guard evloop.tasks.get(fd) is Some(task)
  guard (task.events & Write) != 0
  let coro = @coroutine.current_coroutine()
  task.write.add(coro)
  ignore(@coroutine.suspend()) catch {
    err => {
      task.write.remove(coro)
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
pub async fn perform_job(job : @thread_pool.Job) -> Int raise {
  guard curr_loop.val is Some(evloop)
  let coro = @coroutine.current_coroutine()
  @thread_pool.submit_job(job)
  evloop.jobs[job.id()] = { job, coro }
  @coroutine.protect_from_cancel(@coroutine.suspend)
  if job.err() > 0 {
    raise @os_error.OSError(job.err())
  } else {
    job.ret()
  }
}
