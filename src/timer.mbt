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
/// `sleep` will wait for the given time (in milliseconds) before returning.
/// Other task can still run while current task is sleeping.
/// If current task is cancelled, `sleep` will return early with an error.
pub async fn sleep(duration : Int) -> Unit {
  let coro = @coroutine.current_coroutine()
  let timer = @event_loop.Timer::new(duration, () => coro.wake())
  defer timer.cancel()
  @coroutine.suspend()
}
