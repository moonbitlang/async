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
priv enum TaskGroupState {
  Done
  Fail(Error)
  Running
}

///|
/// A `TaskGroup` can be used to spawn children tasks that run in parallel.
/// Task groups implements *structured concurrency*:
/// a task group will only return after all its children task terminates.
///
/// Task groups also handles *error propagation*:
/// by default, if any child task raises error,
/// the whole task group will also raise that error,
/// and all other remaining child tasks will be cancelled.
///
/// The type parameter `X` in `TaskGroup[X]` is the result type of the group,
/// see `with_task_group` for more detail.
struct TaskGroup[X] {
  children : Array[@coroutine.Coroutine]
  parent : @coroutine.Coroutine
  mut unfinished : Int
  mut state : TaskGroupState
  mut result : X?
}

///|
fn[X] TaskGroup::cancel(self : TaskGroup[X], err : Error) -> Unit {
  let old_state = self.state
  match old_state {
    Done(_) | Fail(_) if err is @coroutine.Cancelled => ()
    _ => self.state = Fail(err)
  }
  if old_state is Running {
    for child in self.children {
      child.cancel()
    }
  }
}

///|
pub suberror AlreadyTerminated derive(Show)

///|
fn[X] TaskGroup::spawn_coroutine(
  self : TaskGroup[X],
  f : async () -> Unit raise,
  no_wait~ : Bool,
  allow_failure~ : Bool,
) -> @coroutine.Coroutine raise {
  if not(self.state is Running) {
    raise AlreadyTerminated
  }
  if not(no_wait) {
    self.unfinished += 1
  }
  fn on_completion() {
    if not(no_wait) {
      self.unfinished -= 1
      if self.unfinished == 0 {
        self.parent.wake()
      }
    }
  }

  fn on_error(err) {
    if not(allow_failure) {
      self.cancel(err)
    }
    on_completion()
  }

  async fn worker() raise {
    f()
    on_completion()
  }

  let coro = @coroutine.spawn(worker, on_error~)
  self.children.push(coro)
  coro
}

///|
/// Spawn a child task in a task group, and run it asynchronously in the background.
///
/// Unless `no_wait` (`false` by default) is `true`,
/// the whole task group will only exit after this child task terminates.
///
/// Unless `allow_failure` (`false` by default) is `true`,
/// Ithe whole task group will also fail if the spawned task fails, 
/// other tasks in the group will be cancelled in this case.
///
/// If the task group is already cancelled or has been terminated,
/// `spawn_bg` will fail with error and the child task will not be spawned.
///
/// It is undefined whether the child task will start running immediately
/// before `spawn_bg` returns.
pub fn[X] TaskGroup::spawn_bg(
  self : TaskGroup[X],
  f : async () -> Unit raise,
  no_wait~ : Bool = false,
  allow_failure~ : Bool = false,
) -> Unit raise {
  ignore(self.spawn_coroutine(f, no_wait~, allow_failure~))
}

///|
/// Spawn a child task in a task group, compute a result asynchronously.
/// A task handle will be returned, the result value of the task can be waited
/// and retrieved using `.wait()`, or cancelled using `.cancel()`.
///
/// Unless `no_wait` (`false` by default) is `true`,
/// the whole task group will only exit after this child task terminates.
///
/// Unless `allow_failure` (`false` by default) is `true`,
/// Ithe whole task group will also fail if the spawned task fails, 
/// other tasks in the group will be cancelled in this case.
///
/// If the task group is already cancelled or has been terminated,
/// `spawn` will fail with error and the child task will not be spawned.
///
/// It is undefined whether the child task will start running immediately
/// before `spawn` returns.
pub fn[G, X] TaskGroup::spawn(
  self : TaskGroup[G],
  f : async () -> X raise,
  no_wait~ : Bool = false,
  allow_failure~ : Bool = false,
) -> Task[X] raise {
  let value = @ref.new(None)
  let coro = self.spawn_coroutine(
    () => value.val = Some(f()),
    no_wait~,
    allow_failure~,
  )
  { value, coro }
}

///|
/// `with_task_group(f)` creates a new task group and run `f` with the new group.
/// `f` itself will be run in a child task of the new group.
/// `with_task_group` exits after all the whole group terminates,
/// which means all child tasks in the group have terminated, including `f`.
///
/// If all children task terminate successfully,
/// `with_task_group` will return the result of `f`.
pub async fn[X] with_task_group(f : async (TaskGroup[X]) -> X raise) -> X raise {
  let tg = {
    children: [],
    parent: @coroutine.current_coroutine(),
    unfinished: 0,
    state: Running,
    result: None,
  }
  tg.spawn_bg(fn() {
    let value = f(tg)
    if tg.result is None {
      tg.result = Some(value)
    }
  })
  if tg.unfinished > 0 {
    @coroutine.suspend() catch {
      err => tg.cancel(err)
    }
  }
  if tg.state is Running {
    tg.state = Done
    for child in tg.children {
      child.cancel()
    }
  }
  tg.children.clear()
  match tg.state {
    Done => tg.result.unwrap()
    Fail(err) => raise err
    Running => panic()
  }
}

///|
/// Force a task group to terminate immediately with the given result value.
/// All child tasks in the group, including potentially the current one,
/// will be cancelled.
pub fn[X] TaskGroup::return_immediately(
  self : TaskGroup[X],
  value : X,
) -> Unit raise {
  if self.result is None {
    self.result = Some(value)
  }
  if self.state is Running {
    self.state = Done
    let curr_coro = @coroutine.current_coroutine()
    for child in self.children {
      if child != curr_coro {
        child.cancel()
      }
    }
  }
  raise @coroutine.Cancelled
}
