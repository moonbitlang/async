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
priv struct Backend {
  poll : Instance
  fds : Map[@fd_util.Fd, IoHandle]
  pids : Map[Int, Unit]
  timer_waiters : Map[Int, Int64]
  read_waiters : Map[@fd_util.Fd, Int]
  write_waiters : Map[@fd_util.Fd, Int]
  process_waiters : Map[Int, Int]
  completion_waiters : Map[Int, Int]
  notify_recv : @fd_util.Fd
  notify_send : @fd_util.Fd
  mut operation_id : Int
  thread_pool : ThreadPool
  completed_jobs_buffer : FixedArray[Int]
  mut main : @coroutine.Coroutine?
  mut killed_by_signal : Int?
}

///|
#cfg(not(platform="windows"))
fn Backend::new() -> Backend raise {
  let poll = Instance::new()
  let (notify_recv, notify_send) = @fd_util.pipe(
    read_end_is_async=true,
    write_end_is_async=false,
    context="initialze runtime",
  )
  poll.register(notify_recv, prev_events=NoEvent, new_events=ReadEvent) catch {
    err => {
      @fd_util.close(notify_recv, kind=Pipe, context="initialize runtime")
      @fd_util.close(notify_send, kind=Pipe, context="initialize runtime")
      raise err
    }
  }
  init_thread_pool_ffi(notify_send)
  {
    poll,
    fds: {},
    pids: {},
    timer_waiters: {},
    read_waiters: {},
    write_waiters: {},
    process_waiters: {},
    completion_waiters: {},
    notify_recv,
    notify_send,
    operation_id: 0,
    thread_pool: ThreadPool::new(max_worker_count=1024),
    completed_jobs_buffer: FixedArray::make(1024, 0),
    main: None,
    killed_by_signal: None,
  }
}

///|
#cfg(not(platform="windows"))
fn Backend::destroy(backend : Backend, _evloop : EventLoop) -> Unit {
  @fd_util.close(backend.notify_recv, kind=Pipe, context="initialize runtime") catch {
    _ => ()
  }
  @fd_util.close(backend.notify_send, kind=Pipe, context="initialize runtime") catch {
    _ => ()
  }
  backend.poll.remove(backend.notify_recv, events=ReadEvent) catch {
    _ => ()
  }
  backend.poll.destroy()
  destroy_thread_pool()
}

///|
#cfg(not(platform="windows"))
fn Backend::poll(
  backend : Backend,
  evloop : EventLoop,
  blocking~ : Bool,
) -> Array[Int] raise {
  let timeout = backend.next_timer_timeout(evloop, blocking~)
  let n = backend.poll.wait(timeout~)
  if n < 0 {
    @os_error.check_errno("runtime internal: poll_wait")
  }
  let ready = backend.ready_timers(evloop)
  for i in 0..<n {
    let event = get_event(i)
    let events = event.events()
    let fd = event.fd()
    if (events & ProcessEvent) != 0 {
      if backend.process_waiters.get(fd) is Some(subscription_id) {
        ready.push(subscription_id)
      }
    } else if fd == backend.notify_recv {
      while true {
        let bytes_transferred = fetch_completion_ffi(
          backend.notify_recv,
          backend.completed_jobs_buffer,
        )
        if bytes_transferred < 0 {
          @os_error.check_errno("runtime internal: failed to get completed job")
        }
        let n = bytes_transferred / 4
        for i in 0..<n {
          if backend.ready_thread_pool_completion(
              backend.completed_jobs_buffer[i],
            )
            is Some(subscription_id) {
            ready.push(subscription_id)
          }
        }
        if n < backend.completed_jobs_buffer.length() {
          break
        }
      }
    } else if backend.fds.get(fd) is Some(_) {
      if (events & ReadEvent) != 0 {
        if backend.read_waiters.get(fd) is Some(subscription_id) {
          ready.push(subscription_id)
        }
      }
      if (events & WriteEvent) != 0 {
        if backend.write_waiters.get(fd) is Some(subscription_id) {
          ready.push(subscription_id)
        }
      }
    }
  }
  ready
}

///|
#cfg(not(platform="windows"))
fn Backend::cleanup(backend : Backend, _evloop : EventLoop) -> Unit raise {
  for hook in hooks {
    if hook.exit is Some(exit) {
      exit()
    }
  }
  for fd, handle in backend.fds {
    if handle.read is Some(coro) {
      coro.cancel()
    }
    if handle.write is Some(coro) {
      coro.cancel()
    }
    if !(handle.events is NoEvent) {
      // If `poll_register` fails, `handle.events` may be `NoEvent`; in that
      // case the fd was never added to the poller and must not be removed here.
      backend.poll.remove(fd, events=handle.events)
    }
    @fd_util.close(
      fd,
      kind=handle.kind,
      context="runtime internal: close leaking fd",
    )
  }
  backend.check_fd_leak()
  backend.fds.clear()
  for pid, _ in backend.pids {
    backend.poll.remove_pid(pid)
  }
  backend.pids.clear()
  backend.timer_waiters.clear()
  backend.read_waiters.clear()
  backend.write_waiters.clear()
  backend.process_waiters.clear()
  backend.completion_waiters.clear()
  backend.thread_pool.cleanup()
}
