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
  children : Set[@coroutine.Coroutine]
  parent : @coroutine.Coroutine
  mut waiting : Int
  mut state : TaskGroupState
  mut result : X?
  group_defer : Array[async () -> Unit raise]
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
    self.waiting += 1
  }
  async fn worker() raise {
    let coro = @coroutine.current_coroutine()
    defer {
      if not(no_wait) {
        self.waiting -= 1
        if self.waiting == 0 && self.state is Running {
          for child in self.children {
            child.cancel()
          }
          self.state = Done
        }
      }
      if self.children.is_empty() {
        self.parent.wake()
      }
    }
    try {
      defer self.children.remove(coro)
      f()
    } catch {
      err if allow_failure => raise err
      err => {
        if self.state is Running {
          for child in self.children {
            child.cancel()
          }
          self.state = Fail(err)
        } else if not(err is @coroutine.Cancelled) {
          self.state = Fail(err)
        }
        raise err
      }
    }
  }

  let coro = @coroutine.spawn(worker)
  self.children.add(coro)
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
/// Attach a defer block, represented as a cleanup function, to a task group.
/// The clenaup function will be invoked when the group terminates.
/// Group scoped defer blocks are executed in FILO order, just like normal `defer`.
/// `with_task_group` will only exit after all group defer blocks terminate.
///
/// Note that if the whole task group is cancelled,
/// async operations in group defer block will be cancelled immediately too.
/// Users can use `protect_from_cancel` to prevent async tasks from being cancelled.
/// It is highly recommended to add a hard timeout to async defer block in this case,
/// to avoid infinite hanging due to blocked operation.
pub fn[X] TaskGroup::add_defer(
  self : TaskGroup[X],
  block : async () -> Unit raise,
) -> Unit raise {
  if not(self.state is Running) {
    raise AlreadyTerminated
  }
  self.group_defer.push(block)
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
    children: Set::new(),
    parent: @coroutine.current_coroutine(),
    waiting: 0,
    state: Running,
    result: None,
    group_defer: [],
  }
  tg.spawn_bg(fn() {
    let value = f(tg)
    if tg.result is None {
      tg.result = Some(value)
    }
  })
  if not(tg.children.is_empty()) {
    @coroutine.suspend() catch {
      err =>
        if tg.state is Running {
          tg.state = Fail(err)
          for child in tg.children {
            child.cancel()
          }
        }
    }
  }
  if not(tg.children.is_empty()) {
    protect_from_cancel(@coroutine.suspend) catch {
      _ => ()
    }
  }
  tg.children.clear()
  while tg.group_defer.pop() is Some(defer_block) {
    defer_block() catch {
      err => if tg.state is Done { tg.state = Fail(err) }
    }
  }
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

///|
pub(all) enum RetryMethod {
  NoRetry
  Immediate
  FixedDelay(Int)
  ExponentialDelay(initial~ : Int, factor~ : Double, maximum~ : Int)
}

///|
/// Similar to `spawn_bg`, but the spawn a loop,
/// i.e. the spawned task will be restarted after it terminates.
/// The spawned task can terminate the loop by returning `IterEnd`.
///
/// When the spawned task raises an error, the behavior is determined by `retry`.
/// - If `retry` is `NoRetry` (the default),
///   the loop will terminate immediately and propagate the error.
/// - If `retry` is `Immediate`, the task will immediately be restarted.
/// - If `retry` is `FixedDelay(t)`,
///   the task will be restarted after sleeping for `t` milliseconds
/// - If `retry` is `ExponentialDelay(initial~, factor~, maximum~)`,
///   the task will be restarted with an exponentially growing delay.
///   The initial delay is `initial`, and after every failure,
///   the delay will be multiplied by `factor`, but will never exceed `maximum`.
///   If the task succeed, the retry delay will be reset to `initial`.
///
/// The meaning of `no_wait` and `allow_failure` is the same as `spawn_bg`.
pub fn[X] TaskGroup::spawn_loop(
  self : TaskGroup[X],
  f : async () -> IterResult raise,
  no_wait~ : Bool = false,
  allow_failure~ : Bool = false,
  retry~ : RetryMethod = NoRetry,
) -> Unit raise {
  self.spawn_bg(no_wait~, allow_failure~, fn() {
    match retry {
      NoRetry =>
        for {
          guard f() is IterContinue else { break }
        }
      Immediate =>
        for {
          try f() catch {
            err if @coroutine.is_being_cancelled() => raise err
            _ => ()
          } noraise {
            IterContinue => ()
            IterEnd => break
          }
        }
      FixedDelay(t) =>
        for {
          try f() catch {
            err if @coroutine.is_being_cancelled() => raise err
            _ => sleep(t)
          } noraise {
            IterContinue => ()
            IterEnd => break
          }
        }
      ExponentialDelay(initial~, factor~, maximum~) =>
        for delay = initial {
          try f() catch {
            err if @coroutine.is_being_cancelled() => raise err
            _ => {
              sleep(delay)
              continue @cmp.minimum(
                  maximum,
                  (delay.to_double() * factor).to_int(),
                )
            }
          } noraise {
            IterContinue => continue initial
            IterEnd => break
          }
        }
    }
  })
}
