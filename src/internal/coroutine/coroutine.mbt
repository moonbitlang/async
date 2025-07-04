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
  Suspend(ok_cont~ : (Int) -> Unit, err_cont~ : (Error) -> Unit)
}

///|
struct Coroutine {
  coro_id : Int
  mut state : State
  downstream : Map[Coroutine, Int]
  children : Array[Coroutine]
  children_wait : Array[Coroutine]
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
let coro_id : Ref[Int] = @ref.new(0)

///|
let curr_coro : Ref[Coroutine?] = { val: None }

///|
pub fn current_coroutine() -> Coroutine {
  curr_coro.val.unwrap()
}

///|
pub fn Coroutine::wake(self : Coroutine, tag~ : Int = 0) -> Unit {
  guard self.state is Suspend(ok_cont~, err_cont=_) else {  }
  self.state = Running
  let last_coro = curr_coro.val
  curr_coro.val = Some(self)
  ok_cont(tag)
  curr_coro.val = last_coro
}

///|
pub suberror Cancelled derive(Show)

///|
pub fn Coroutine::cancel(self : Coroutine) -> Unit {
  guard self.state is Suspend(ok_cont=_, err_cont~) else {  }
  self.state = Running
  let last_coro = curr_coro.val
  curr_coro.val = Some(self)
  err_cont(Cancelled)
  curr_coro.val = last_coro
}

///|
pub async fn suspend() -> Int raise {
  guard curr_coro.val is Some(coro)
  async_suspend(fn(ok_cont, err_cont) {
    guard coro.state is Running
    coro.state = Suspend(ok_cont~, err_cont~)
  })
}

///|
pub fn Coroutine::spawn(f : async () -> Unit raise, wait~ : Bool) -> Coroutine {
  coro_id.val += 1
  let coro = {
    state: Running,
    downstream: {},
    children: [],
    children_wait: [],
    coro_id: coro_id.val,
  }
  let last_coro = curr_coro.val
  if last_coro is Some(outer) {
    if wait {
      outer.children_wait.push(coro)
    } else {
      outer.children.push(coro)
    }
  }
  curr_coro.val = Some(coro)
  run_async(fn() {
    try {
      f()
      wait_all(coro.children_wait)
    } catch {
      err => coro.state = Fail(err)
    } noraise {
      _ => coro.state = Done
    }
    for coro, tag in coro.downstream {
      coro.wake(tag~)
    }
    coro.downstream.clear()
    for child in coro.children {
      child.cancel()
    }
    coro.children.clear()
    for child in coro.children_wait {
      child.cancel()
    }
    coro.children_wait.clear()
  })
  curr_coro.val = last_coro
  coro
}

///|
pub fnalias Coroutine::spawn

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
  guard curr_coro.val is Some(coro)
  guard not(physical_equal(coro, target))
  match target.state {
    Done => return
    Fail(err) => raise err
    Running | Suspend(_) => ()
  }
  target.downstream[coro] = 0
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
pub async fn wait_all(coros : Array[Coroutine]) -> Unit raise {
  guard curr_coro.val is Some(self)
  let mut remaining = 0
  try {
    for tag, coro in coros {
      guard not(physical_equal(coro, self))
      match coro.state {
        Done => ()
        Fail(err) => raise err
        Running | Suspend(_) => {
          remaining += 1
          coro.downstream[self] = tag
        }
      }
    }
    while remaining > 0 {
      let tag = suspend()
      match coros[tag].state {
        Done => remaining -= 1
        Fail(err) => raise err
        Running | Suspend(_) => ()
      }
    }
  } catch {
    err => {
      for coro in coros {
        match coro.state {
          Running | Suspend(_) => coro.downstream.remove(self)
          Done | Fail(_) => ()
        }
      }
      raise err
    }
  }
}
