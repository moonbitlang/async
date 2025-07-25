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
priv enum State {
  Done
  Fail(Error)
  Running
  Suspend(ok_cont~ : (Unit) -> Unit, err_cont~ : (Error) -> Unit)
}

///|
struct Coroutine {
  coro_id : Int
  mut state : State
  mut shielded : Bool
  mut cancelled : Bool
  mut ready : Bool
  downstream : Set[Coroutine]
}

///|
pub impl Eq for Coroutine with op_equal(c1, c2) {
  c1.coro_id == c2.coro_id
}

///|
pub impl Hash for Coroutine with hash_combine(self, hasher) {
  self.coro_id.hash_combine(hasher)
}

///|
pub fn Coroutine::wake(self : Coroutine) -> Unit {
  self.ready = true
  scheduler.run_later.push_back(self)
}

///|
pub fn is_being_cancelled() -> Bool {
  current_coroutine().cancelled
}

///|
pub(all) suberror Cancelled derive(Show)

///|
pub fn Coroutine::cancel(self : Coroutine) -> Unit {
  self.cancelled = true
  if not(self.shielded || self.ready) {
    self.wake()
  }
}

///|
pub async fn pause() -> Unit raise {
  guard scheduler.curr_coro is Some(coro)
  if coro.cancelled && not(coro.shielded) {
    raise Cancelled
  }
  async_suspend(fn(ok_cont, err_cont) {
    guard coro.state is Running
    coro.state = Suspend(ok_cont~, err_cont~)
    coro.ready = true
    scheduler.run_later.push_back(coro)
  })
}

///|
pub async fn suspend() -> Unit raise {
  guard scheduler.curr_coro is Some(coro)
  if coro.cancelled && not(coro.shielded) {
    raise Cancelled
  }
  scheduler.blocking += 1
  defer {
    scheduler.blocking -= 1
  }
  async_suspend(fn(ok_cont, err_cont) {
    guard coro.state is Running
    coro.state = Suspend(ok_cont~, err_cont~)
  })
}

///|
pub async fn sleep(duration : Int) -> Unit raise {
  let timer = Timer::new(duration, current_coroutine())
  scheduler.timers.add(timer)
  suspend() catch {
    err => {
      scheduler.timers.remove(timer)
      raise err
    }
  }
}

///|
pub fn spawn(f : async () -> Unit raise) -> Coroutine {
  scheduler.coro_id += 1
  let coro = {
    state: Running,
    ready: false,
    shielded: false,
    downstream: Set::new(),
    coro_id: scheduler.coro_id,
    cancelled: false,
  }
  let last_coro = scheduler.curr_coro
  scheduler.curr_coro = Some(coro)
  run_async(fn() {
    try {
      pause()
      f()
    } catch {
      err => coro.state = Fail(err)
    } noraise {
      _ => coro.state = Done
    }
    for coro in coro.downstream {
      coro.wake()
    }
    coro.downstream.clear()
  })
  scheduler.curr_coro = last_coro
  coro
}

///|
pub fn Coroutine::unwrap(self : Coroutine) -> Unit raise {
  match self.state {
    Done => ()
    Fail(err) => raise err
    Running | Suspend(_) => panic()
  }
}

///|
pub async fn Coroutine::wait(target : Coroutine) -> Unit raise {
  guard scheduler.curr_coro is Some(coro)
  guard not(physical_equal(coro, target))
  match target.state {
    Done => return
    Fail(err) => raise err
    Running | Suspend(_) => ()
  }
  target.downstream.add(coro)
  try suspend() catch {
    err => {
      target.downstream.remove(coro)
      raise err
    }
  } noraise {
    _ => target.unwrap()
  }
}

///|
pub async fn protect_from_cancel(f : async () -> Unit raise) -> Unit raise {
  guard scheduler.curr_coro is Some(coro)
  if coro.shielded {
    // already in a shield, do nothing
    f()
  } else {
    coro.shielded = true
    defer {
      coro.shielded = false
    }
    f()
    if coro.cancelled {
      raise Cancelled
    }
  }
}
