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
struct Semaphore {
  mut value : Int
  size : Int
  waiters : @deque.Deque[Ref[@coroutine.Coroutine?]]
}

///|
/// Create a semaphore of size `size`,
/// the initial value of the semaphore
/// will be set to `initial_value` (`size` by default)
pub fn Semaphore::new(size : Int, initial_value? : Int = size) -> Semaphore {
  guard initial_value >= 0 && initial_value <= size
  { value: initial_value, size, waiters: @deque.new() }
}

///|
/// Release a unit of resource back to the semaphore. This function never blocks.
/// If there are waiters currently blocked on the semaphore,
/// the first waiter will be woken to acquire the resource.
///
/// `release` must be called after a successful `acquire`,
/// in strictly one-to-one manner.
/// If the value of the semaphore exceed its size,
/// `release` will abort immediately.
pub fn Semaphore::release(self : Semaphore) -> Unit {
  if self.value >= self.size {
    abort("semaphore: too many release")
  }
  loop self.waiters.pop_front() {
    None => self.value += 1
    Some({ val: None }) => continue self.waiters.pop_front()
    Some({ val: Some(waiter) }) => waiter.wake()
  }
}

///|
/// Acquire one unit of resource from the semaphore.
/// If no resource is available,
/// `acquire` will block and wait until any resource is available.
/// If there are multiple tasks both waiting for the same resource,
/// new resource will be delivered in a first-come-first-serve manner.
///
/// `acquire` itself never fail, and will wait indefinitely.
/// However, since `acquire` is a blocking point,
/// the task running `acquire` may be cancelled,
/// in this case, an cancellation will be raised from `acquire`.
pub async fn Semaphore::acquire(self : Semaphore) -> Unit {
  if self.value > 0 {
    self.value -= 1
  } else {
    let waiter = @ref.new(Some(@coroutine.current_coroutine()))
    self.waiters.push_back(waiter)
    @coroutine.suspend() catch {
      err => {
        waiter.val = None
        raise err
      }
    }
  }
}

///|
/// Try to acquire one unit of resource from the semaphore.
/// If resource is successfully acquired, `true` is returned,
/// Otherwise, `false` is returned immediately without blocking.
pub fn Semaphore::try_acquire(self : Semaphore) -> Bool {
  if self.value > 0 {
    self.value -= 1
    true
  } else {
    false
  }
}
