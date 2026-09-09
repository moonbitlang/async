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
pub enum SuspendResult {
  Continue
  Cancelled
}

///|
priv enum State {
  Done
  Fail(Error)
  Cancelled
  Running
  Suspend((SuspendResult) -> Unit)
}

///|
pub struct Coroutine {
  priv coro_id : Int
  priv mut state : State
  priv mut shielded : Bool
  priv mut cancelled : Bool
  priv mut ready : Bool
  priv downstream : Set[Coroutine]
  loc : SourceLoc
}

///|
pub impl Eq for Coroutine with fn equal(c1, c2) {
  c1.coro_id == c2.coro_id
}

///|
pub impl Hash for Coroutine with fn hash_combine(self, hasher) {
  Hash::hash_combine(self.coro_id, hasher)
}

///|
pub fn Coroutine::wake(self : Coroutine) -> Unit {
  if !self.ready {
    self.ready = true
    scheduler.run_later.push_back(self)
  }
}

///|
pub fn is_being_cancelled() -> Bool {
  let coro = current_coroutine()
  coro.cancelled && !coro.shielded
}

///|
pub async fn check_cancellation() -> Unit noraise {
  if is_being_cancelled() {
    raise_cancellation_signal()
  }
}

///|
pub fn Coroutine::cancel(self : Coroutine) -> Unit {
  self.cancelled = true
  if !self.shielded {
    self.wake()
  }
}

///|
pub async fn pause() -> Unit noraise {
  guard! scheduler.curr_coro is Some(coro)
  if coro.cancelled && !coro.shielded {
    raise_cancellation_signal()
  }
  let result = async_suspend() <| cont => {
    guard! coro.state is Running
    coro.state = Suspend(cont)
    coro.ready = true
    scheduler.run_later.push_back(coro)
  }
  match result {
    Continue => ()
    Cancelled => raise_cancellation_signal()
  }
}

///|
pub async fn suspend_check_cancel() -> SuspendResult noraise {
  guard! scheduler.curr_coro is Some(coro)
  if coro.cancelled && !coro.shielded {
    return Cancelled
  }
  async_suspend() <| cont => {
    guard! coro.state is Running
    coro.state = Suspend(cont)
  }
}

///|
pub async fn suspend() -> Unit noraise {
  match suspend_check_cancel() {
    Continue => ()
    Cancelled => raise_cancellation_signal()
  }
}

///|
#callsite(autofill(loc))
pub fn spawn(f : async () -> Unit, loc~ : SourceLoc) -> Coroutine {
  scheduler.coro_id += 1
  let coro = {
    state: Running,
    ready: true,
    shielded: false,
    downstream: Set([]),
    coro_id: scheduler.coro_id,
    cancelled: false,
    loc,
  }
  fn run(_) {
    // The parameter (suspend result) is deliberately ignored here.
    // We want to ensure the body of coroutine always get a chance to execute,
    // even if cancelled immediately before starting.
    // This way, the user can rely on `defer` at the start of coroutine body
    // always getting triggered, which is useful for many programming patterns.
    run_async() <| () => {
      try capture_cancellation(f, handler=() => coro.state = Cancelled) catch {
        err => coro.state = Fail(err)
      } noraise {
        _ if coro.state is Running => coro.state = Done
        _ => ()
      }
      for coro in coro.downstream {
        coro.wake()
      }
      scheduler.all_coros.remove(coro)
    }
  }

  coro.state = Suspend(run)
  scheduler.run_later.push_back(coro)
  scheduler.all_coros.add(coro)
  coro
}

///|
pub fn Coroutine::unwrap(self : Coroutine) -> SuspendResult raise {
  match self.state {
    Done => Continue
    Cancelled => Cancelled
    Fail(err) => raise err
    Running | Suspend(_) => panic()
  }
}

///|
pub async fn Coroutine::wait(target : Coroutine) -> SuspendResult {
  guard! scheduler.curr_coro is Some(coro)
  guard! !physical_equal(coro, target)
  match target.state {
    Done => return Continue
    Cancelled => return Cancelled
    Fail(err) => raise err
    Running | Suspend(_) => ()
  }
  target.downstream.add(coro)
  defer target.downstream.remove(coro)
  suspend()
  target.unwrap()
}

///|
pub fn Coroutine::check_error(coro : Coroutine) -> Unit raise {
  match coro.state {
    Fail(err) => raise err
    Done | Cancelled | Running | Suspend(_) => ()
  }
}

///|
pub async fn[X] protect_from_cancel(f : async () -> X) -> X nocancel {
  guard! scheduler.curr_coro is Some(coro)
  // When `coro.shielded` is `true`, the scheduler never cancel this coroutine,
  // so `capture_cancellation` here is unnecessary, just for fixing the type
  capture_cancellation(handler=() => panic()) <| () => {
    if coro.shielded {
      // already in a shield, do nothing
      f()
    } else {
      coro.shielded = true
      defer {
        coro.shielded = false
      }
      f()
    }
  }
}

///|
pub async fn[X] handle_cancellation(f : async () -> X) -> X? {
  capture_cancellation(handler=() => None, () => Some(f()))
}
