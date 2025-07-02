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
  mut state : State
  downstream : Array[Coroutine]
}

///|
let curr_coro : Ref[Coroutine?] = { val: None }

///|
pub fn current_coroutine() -> Coroutine {
  curr_coro.val.unwrap()
}

///|
pub fn Coroutine::wake(self : Coroutine) -> Unit {
  guard self.state is Suspend(ok_cont~, err_cont=_) else {  }
  self.state = Running
  let last_coro = curr_coro.val
  curr_coro.val = Some(self)
  ok_cont(())
  curr_coro.val = last_coro
}

///|
pub fn Coroutine::cancel(self : Coroutine, err~ : Error) -> Unit {
  guard self.state is Suspend(ok_cont=_, err_cont~) else {  }
  self.state = Running
  let last_coro = curr_coro.val
  curr_coro.val = Some(self)
  err_cont(err)
  curr_coro.val = last_coro
}

///|
pub async fn suspend() -> Unit raise {
  guard curr_coro.val is Some(coro)
  async_suspend(fn(ok_cont, err_cont) {
    guard coro.state is Running
    coro.state = Suspend(ok_cont~, err_cont~)
  })
}

///|
pub fn Coroutine::spawn(f : async () -> Unit raise) -> Coroutine {
  let coro = { state: Running, downstream: [] }
  let last_coro = curr_coro.val
  curr_coro.val = Some(coro)
  run_async(fn() {
    try f() catch {
      err => coro.state = Fail(err)
    } noraise {
      _ => coro.state = Done
    }
    for downstream in coro.downstream {
      downstream.wake()
    }
    coro.downstream.clear()
  })
  curr_coro.val = last_coro
  coro
}

///|
pub fnalias Coroutine::spawn

///|
pub async fn Coroutine::wait(target : Coroutine) -> Unit raise {
  guard curr_coro.val is Some(coro)
  guard not(physical_equal(coro, target))
  match target.state {
    Done => ()
    Fail(err) => raise err
    Running | Suspend(_) => {
      target.downstream.push(coro)
      suspend()
    }
  }
  loop target.state {
    Done => ()
    Fail(err) => raise err
    Running | Suspend(_) => {
      suspend()
      continue target.state
    }
  }
}
