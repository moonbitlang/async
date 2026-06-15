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
#cfg(platform="windows")
priv struct Backend {
  poll : Instance
  fds : Map[@fd_util.Fd, IoHandle]
  timer_waiters : Map[Int, Int64]
  read_waiters : Map[@fd_util.Fd, Int]
  write_waiters : Map[@fd_util.Fd, Int]
  process_waiters : Map[Int, Int]
  completion_waiters : Map[Int, Int]
  mut operation_id : Int
  thread_pool : ThreadPool
  mut main : @coroutine.Coroutine?
  mut killed_by_signal : Int?
}

///|
#cfg(platform="windows")
fn Backend::new() -> Backend raise {
  let poll = Instance::new()
  init_thread_pool_ffi(poll.0)
  if init_WSA_ffi() != 0 {
    @os_error.check_errno("initialize WSA")
  }
  {
    poll,
    fds: {},
    timer_waiters: {},
    read_waiters: {},
    write_waiters: {},
    process_waiters: {},
    completion_waiters: {},
    operation_id: 0,
    thread_pool: ThreadPool::new(max_worker_count=1024),
    main: None,
    killed_by_signal: None,
  }
}

///|
#cfg(platform="windows")
fn Backend::destroy(backend : Backend, _evloop : EventLoop) -> Unit {
  backend.poll.destroy()
  destroy_thread_pool()
  ignore(cleanup_WSA_ffi())
}

///|
#cfg(platform="windows")
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
    let fd = event.fd()
    if @fd_util.fd_is_valid(fd) {
      guard backend.fds.get(fd) is Some(_) else { continue }
      let job_id = event.io_result().job_id()
      if backend.completion_waiters.get(job_id) is Some(subscription_id) {
        ready.push(subscription_id)
      }
    } else {
      // Custom completion packet from thread pool.
      let job_id = event.bytes_transferred()
      if backend.ready_thread_pool_completion(job_id) is Some(subscription_id) {
        ready.push(subscription_id)
      }
    }
  }
  ready
}

///|
#cfg(platform="windows")
fn Backend::cleanup(backend : Backend, _evloop : EventLoop) -> Unit raise {
  for hook in hooks {
    if hook.exit is Some(exit) {
      exit()
    }
  }
  for fd, handle in backend.fds {
    @fd_util.close(
      fd,
      kind=handle.kind,
      context="runtime internal: close leaking fd",
    )
  }
  backend.check_fd_leak()
  backend.fds.clear()
  backend.timer_waiters.clear()
  backend.read_waiters.clear()
  backend.write_waiters.clear()
  backend.process_waiters.clear()
  backend.completion_waiters.clear()
  backend.thread_pool.cleanup()
}
