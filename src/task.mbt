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
struct Task[X] {
  coro : @coroutine.Coroutine
  result : Ref[X?]
}

///|
pub async fn[X] Task::wait(task : Task[X]) -> X raise {
  task.coro.wait()
  task.result.val.unwrap()
}

///|
pub fn[X] Task::cancel(task : Task[X]) -> Unit {
  task.coro.cancel()
}

///|
pub async fn[X] spawn(f : async () -> X raise) -> Task[X] {
  let result = @ref.new(None)
  let coro = @coroutine.spawn(wait=false, () => result.val = Some(f()))
  { coro, result }
}

///|
pub async fn spawn_bg(f : async () -> Unit raise) -> Unit {
  ignore(@coroutine.spawn(wait=true, f))
}

///|
pub async fn[X, Y] wait2(t1 : Task[X], t2 : Task[Y]) -> (X, Y) raise {
  @coroutine.wait_all([t1.coro, t2.coro])
  (t1.result.val.unwrap(), t2.result.val.unwrap())
}

///|
pub async fn[X, Y, Z] wait3(
  t1 : Task[X],
  t2 : Task[Y],
  t3 : Task[Z]
) -> (X, Y, Z) raise {
  @coroutine.wait_all([t1.coro, t2.coro, t3.coro])
  (t1.result.val.unwrap(), t2.result.val.unwrap(), t3.result.val.unwrap())
}

///|
pub async fn[X, Y, Z, W] wait4(
  t1 : Task[X],
  t2 : Task[Y],
  t3 : Task[Z],
  t4 : Task[W]
) -> (X, Y, Z, W) raise {
  @coroutine.wait_all([t1.coro, t2.coro, t3.coro, t4.coro])
  (
    t1.result.val.unwrap(),
    t2.result.val.unwrap(),
    t3.result.val.unwrap(),
    t4.result.val.unwrap(),
  )
}
