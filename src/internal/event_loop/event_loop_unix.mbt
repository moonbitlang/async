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
priv struct UnixEventLoopExtra {
  // On Unix-like systems,  we use a pipe to
  // receive completion notification from the thread pool
  notify_recv : @fd_util.Fd
  notify_send : @fd_util.Fd

  // On MacOS, PID waiting is implemented directly via kqueue, 
  // so we need to separately maintain waiters for each PID.
  pids : Map[Int, @coroutine.Coroutine]
  // On Linux/MacOS, notifications for completion of thread pool job
  // are transferred via a pipe, this buffer is used to read from the pipe.
  completed_jobs_buffer : FixedArray[Int]
}

///|
#cfg(not(platform="windows"))
type PlatformEventLoopExtra = UnixEventLoopExtra

///|
#cfg(not(platform="windows"))
fn UnixEventLoopExtra::new(event_bus : EventBus) -> UnixEventLoopExtra raise {
  let (notify_recv, notify_send) = @fd_util.pipe(
    read_end_is_async=true,
    write_end_is_async=false,
    context="initialize runtime",
  )
  event_bus.register(notify_recv, read_only=true) catch {
    err => {
      @fd_util.close(notify_recv, kind=Pipe, context="initialize runtime")
      @fd_util.close(notify_send, kind=Pipe, context="initialize runtime")
      raise err
    }
  }
  init_thread_pool_ffi(notify_send)
  {
    notify_recv,
    notify_send,
    pids: {},
    completed_jobs_buffer: FixedArray::make(1024, 0),
  }
}

///|
#cfg(not(platform="windows"))
fn UnixEventLoopExtra::destroy(self : UnixEventLoopExtra) -> Unit {
  @fd_util.close(self.notify_recv, kind=Pipe, context="initialize runtime") catch {
    _ => ()
  }
  @fd_util.close(self.notify_send, kind=Pipe, context="initialize runtime") catch {
    _ => ()
  }
}

///|
#cfg(not(platform="windows"))
fn UnixEventLoopExtra::cleanup(self : UnixEventLoopExtra) -> Unit {
  for _, coro in self.pids {
    coro.cancel()
  }
  self.pids.clear()
}

///|
#cfg(not(platform="windows"))
fn UnixEventLoopExtra::poll(self : Self, evloop : EventLoop) -> Unit raise {
  let n = evloop.wait_for_event()
  for i in 0..<n {
    let event = get_event(i)
    let events = event.events()
    let fd = event.fd()
    if (events & ProcessEvent) != 0 {
      if self.pids.get(fd) is Some(coro) {
        coro.wake()
      }
    } else if fd == self.notify_recv {
      while true {
        let bytes_transferred = fetch_completion_ffi(
          self.notify_recv,
          self.completed_jobs_buffer,
        )
        if bytes_transferred < 0 {
          @os_error.check_errno("runtime internal: failed to get completed job")
        }
        let n = bytes_transferred / 4
        for i in 0..<n {
          evloop.handle_completed_job(self.completed_jobs_buffer[i])
        }
        if n < self.completed_jobs_buffer.length() {
          break
        }
      }
    } else if evloop.fds.get(fd) is Some(handle) {
      if (events & ReadEvent) != 0 && handle.read is Waiting(coro) {
        coro.wake()
      }
      if (events & WriteEvent) != 0 && handle.write is Waiting(coro) {
        coro.wake()
      }
    }
  }
}
