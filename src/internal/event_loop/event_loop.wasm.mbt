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
pub(all) enum Platform {
  Linux = 0
  MacOS = 1
  Windows = 2
}

///|
fn get_platform() -> Platform = "moonbit_v0" "get_platform"

///|
fn sleep_ms(duration : Int) -> Int = "moonbit_v0" "sleep_ms"

///|
pub let platform : Platform = get_platform()

///|
pub const IS_WINDOWS : Bool = false

///|
pub fn is_windows() -> Bool {
  platform is Windows
}

///|
let _ignore_unused_import : Unit = {
  ignore(@c_buffer.unimplemented)
  ignore(@fd_util.unimplemented)
  ignore(@os_string.unimplemented)
  ignore(@os_error.unimplemented)
}

///|
priv struct EventLoop {
  timers : @sorted_set.SortedSet[Timer]
}

///|
let curr_loop : Ref[EventLoop?] = Ref(None)

///|
priv struct EventLoopHook {
  init : (() -> Unit raise)?
  exit : (() -> Unit raise)?
}

///|
let hooks : Array[EventLoopHook] = []

///|
pub fn register_hook(
  init? : () -> Unit raise,
  exit? : () -> Unit raise,
) -> Unit {
  hooks.push({ init, exit })
}

///|
fn EventLoop::new() -> EventLoop {
  { timers: @sorted_set.SortedSet([]) }
}

///|
fn EventLoop::destroy(_evloop : EventLoop) -> Unit {
  ()
}

///|
pub fn with_event_loop(f : async () -> Unit) -> Unit raise {
  guard curr_loop.val is None
  let evloop = EventLoop::new()
  defer evloop.destroy()
  curr_loop.val = Some(evloop)
  defer {
    curr_loop.val = None
  }
  for hook in hooks {
    if hook.init is Some(init) {
      init()
    }
  }
  let main = @coroutine.spawn(() => f())
  evloop.run_forever()
  main.unwrap()
}

///|
pub fn reschedule() -> Unit {
  @coroutine.reschedule()
}

///|
fn EventLoop::poll(self : EventLoop) -> Unit {
  let has_timers = !self.timers.is_empty()
  let timeout = if @coroutine.has_immediately_ready_task() {
    0
  } else if has_timers && self.timers.iter().head() is Some(timer) {
    @cmp.maximum(0, (timer.expire_time - @time.ms_since_epoch()).to_int())
  } else {
    1
  }
  if timeout > 0 {
    ignore(sleep_ms(timeout))
  }
  if has_timers {
    let now = @time.ms_since_epoch()
    for timer in self.timers {
      if timer.expire_time <= now {
        (timer.callback)()
      } else {
        break
      }
    }
  }
}

///|
fn EventLoop::cleanup(_self : Self) -> Unit raise {
  for hook in hooks {
    if hook.exit is Some(exit) {
      exit()
    }
  }
}

///|
fn EventLoop::run_forever(self : Self) -> Unit raise {
  while !@coroutine.no_more_work() {
    self.poll()
    @coroutine.reschedule()
  }
  self.cleanup()
}

///|
pub let check_fd_leak : Ref[Bool] = Ref(false)

///|
priv enum CancellationStatus {
  NoWait
  NeedWait
  RetryLater
}

///|
async fn perform_job_in_worker(
  job : Job,
  context~ : String,
  cancel? : (Int) -> CancellationStatus raise,
) -> Int {
  ignore(cancel)
  @coroutine.check_cancellation()
  job.run()
  if job.err() is err && err > 0 {
    if errno_is_cancelled(err) {
      raise @coroutine.Cancelled
    } else {
      raise @os_error.OSError(err, context~)
    }
  } else {
    job.ret()
  }
}

///|
fn errno_is_cancelled(errno : Int) -> Bool = "moonbit_v0" "errno_is_cancelled"

///|
fn EventLoop::cancel_job_in_worker(
  _evloop : EventLoop,
  _job_id : Int,
  context~ : String,
) -> CancellationStatus raise {
  ignore(context)
  NoWait
}
