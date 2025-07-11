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
  scheduler.run_later.push_back(self)
}

///|
pub suberror Cancelled derive(Show)

///|
pub fn Coroutine::cancel(self : Coroutine) -> Unit {
  let last_coro = scheduler.curr_coro
  while self.state is Suspend(ok_cont=_, err_cont~) {
    self.state = Running
    scheduler.curr_coro = Some(self)
    err_cont(Cancelled)
    scheduler.curr_coro = last_coro
  }
}

///|
pub async fn pause() -> Unit raise {
  guard scheduler.curr_coro is Some(coro)
  async_suspend(fn(ok_cont, err_cont) {
    guard coro.state is Running
    coro.state = Suspend(ok_cont~, err_cont~)
    scheduler.run_later.push_back(coro)
  })
}

///|
pub async fn suspend() -> Unit raise {
  guard scheduler.curr_coro is Some(coro)
  async_suspend(fn(ok_cont, err_cont) {
    guard coro.state is Running
    fn wrapped_ok_cont(x) {
      scheduler.blocking -= 1
      ok_cont(x)
    }

    fn wrapped_err_cont(err) {
      scheduler.blocking -= 1
      err_cont(err)
    }

    coro.state = Suspend(ok_cont=wrapped_ok_cont, err_cont=wrapped_err_cont)
    scheduler.blocking += 1
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
pub fn spawn(
  f : async () -> Unit raise,
  on_error? : (Error) -> Unit,
) -> Coroutine {
  scheduler.coro_id += 1
  let coro = {
    state: Running,
    downstream: Set::new(),
    coro_id: scheduler.coro_id,
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
    if coro.state is Fail(err) && on_error is Some(on_error) {
      on_error(err)
    }
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
