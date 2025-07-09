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
/// A `TaskGroup` can be used to spawn children tasks that run in parallel.
/// Task groups implements *structured concurrency*:
/// a task group will only return after all its children task terminates.
///
/// Task groups also handles *error propagation*:
/// by default, if any child task raises error,
/// the whole task group will also raise that error,
/// and all other remaining child tasks will be cancelled.
struct TaskGroup {
  children : Array[@coroutine.Coroutine]
  parent : @coroutine.Coroutine
  mut unfinished : Int
  mut err : Error?
}

///|
fn TaskGroup::cancel(self : TaskGroup, err : Error) -> Unit {
  if self.err is None {
    self.err = Some(err)
  }
  for child in self.children {
    child.cancel()
  }
  self.unfinished = 0
  self.parent.wake()
}

///|
fn TaskGroup::spawn_coroutine(
  self : TaskGroup,
  f : async () -> Unit raise,
) -> @coroutine.Coroutine {
  self.unfinished += 1
  async fn worker() raise {
    try f() catch {
      err => {
        self.cancel(err)
        raise err
      }
    } noraise {
      _ => {
        self.unfinished -= 1
        self.parent.wake()
      }
    }
  }

  let coro = @coroutine.spawn(worker)
  self.children.push(coro)
  coro
}

///|
/// Spawn a child task in a task group, and run it asynchronously in the background.
/// The whole task group will only exit after this child task terminates.
/// If the spawned task fail with error, the whole task group will also fail,
/// other tasks in the group will be cancelled.
pub fn TaskGroup::spawn(self : TaskGroup, f : async () -> Unit raise) -> Unit {
  ignore(self.spawn_coroutine(f))
}

///|
pub fn[X] TaskGroup::async_value(
  self : TaskGroup,
  f : async () -> X raise,
) -> AsyncValue[X] {
  let value = @ref.new(None)
  let coro = self.spawn_coroutine(() => value.val = Some(f()))
  { value, coro }
}

///|
/// `with_task_group(f)` creates a new task group and run `f` with the new group.
/// `f` itself will be run in a child task of the new group.
/// `with_task_group` exits after all the whole group terminates,
/// which means all child tasks in the group have terminated, including `f`.
pub async fn[X] with_task_group(f : async (TaskGroup) -> X raise) -> X raise {
  let mut result = None
  let tg = {
    children: [],
    parent: @coroutine.current_coroutine(),
    unfinished: 0,
    err: None,
  }
  tg.spawn(() => result = Some(f(tg)))
  try {
    while tg.unfinished > 0 {
      @coroutine.suspend()
    }
  } catch {
    err => tg.cancel(err)
  }
  match tg.err {
    None => result.unwrap()
    Some(err) => raise err
  }
}
