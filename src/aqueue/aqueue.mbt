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
priv struct Reader[X] {
  /// the value provided the reader.
  /// `value` must be `Some(_)` when the reader is woken
  mut value : X?
  /// `None` indicates that the reader is cancelled
  mut coro : @coroutine.Coroutine?
}

///|
/// An asynchronous queue, where reader can wait for data to arrive
/// in a non-blocking manner.
/// The internal buffer size of this queue is unlimited,
/// and writing to the queue will never block.
struct Queue[X] {
  readers : @deque.Deque[Reader[X]]
  /// invariant: if `buffer` is non-empty, `readers` must be empty
  buffer : @deque.Deque[X]
}

///|
/// Create an empty queue.
#as_free_fn
pub fn[X] Queue::new() -> Queue[X] {
  { readers: @deque.new(), buffer: @deque.new() }
}

///|
/// Put a new element into a queue. This function never blocks.
/// If the queue is currently empty and there are readers blocked on this thread,
/// one reader will be woken to process the data.
pub fn[X] Queue::put(self : Queue[X], data : X) -> Unit {
  loop self.readers.pop_front() {
    None => self.buffer.push_back(data)
    Some({ coro: None, .. }) => continue self.readers.pop_front()
    Some({ coro: Some(coro), .. } as reader) => {
      // after waking the reader, it may not start execution immediately.
      // And a lot of things could happen in the middle.
      // So instead of using `self.buffer`,
      // we pass `data` to the woker reader in a point-to-point manner
      // to avoid some edge cases.
      reader.value = Some(data)
      coro.wake()
    }
  }
}

///|
/// Fetch an element from the queue.
/// If the queue is currently empty, `get` will block and wait until data arrive.
/// If there are multiple readers blocked on `get`,
/// new data will be delivered in a first-come-first-serve manner.
///
/// `get` itself never fail, and will wait indefinitely.
/// However, since `get` is a blocking point, the task running `get` may be cancelled,
/// in this case, an cancellation will be raised from `get`.
pub async fn[X] Queue::get(self : Queue[X]) -> X {
  if self.buffer.pop_front() is Some(data) {
    return data
  }
  let reader = { value: None, coro: Some(@coroutine.current_coroutine()) }
  self.readers.push_back(reader)
  @coroutine.suspend() catch {
    _ if reader.value is Some(value) =>
      // This may happen if:
      //
      // - `put` is called, the value is removed from the queue
      //   and assigned to `reader.value`
      // - the task is called after `put`, before `get` is actually woken
      //
      // In this case, if we cancel `get`,
      // the value would be swollen, which is incorrect.
      // It is also difficult to put the value back to the queue
      // while maintaining correct order.
      // So we choose to swallow the cancellation signal here,
      // which is fine because cancellation is level-triggered.
      return value
    err => {
      reader.coro = None
      raise err
    }
  }
  reader.value.unwrap()
}

///|
/// Try to fetch an element from the queue without blocking.
/// If no element is in the queue at the moment, `None` is returned.
pub fn[X] Queue::try_get(self : Queue[X]) -> X? {
  self.buffer.pop_front()
}
