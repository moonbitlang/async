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
/// An asynchronous queue, where reader can wait for data to arrive
/// in a non-blocking manner.
/// The internal buffer size of this queue is unlimited,
/// and writing to the queue will never block.
struct Queue[X] {
  readers : @deque.Deque[Ref[@coroutine.Coroutine?]]
  buffer : @deque.Deque[X]
}

///|
/// Create an empty queue.
pub fn[X] Queue::new() -> Queue[X] {
  { readers: @deque.new(), buffer: @deque.new() }
}

///|
/// Put a new element into a queue. This function neven blocks.
/// If the queue is currently empty and there are readers blocked on this thread,
/// one reader will be woken to process the data.
pub fn[X] Queue::put(self : Queue[X], data : X) -> Unit {
  self.buffer.push_back(data)
  loop self.readers.pop_front() {
    None => ()
    Some({ val: None }) => continue self.readers.pop_front()
    Some({ val: Some(reader) }) => reader.wake()
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
  loop self.buffer.pop_front() {
    Some(data) => {
      // It is necessary to `pause` here for fairness.
      // Assume there are multiple blocked readers, and now multiple element arrives,
      // we expect this currently blocked readers to continue in
      // first-come-first-serve manner. However, if the first woken reader continues
      // reading, without pausing in the middle, it will receive extra data before
      // the other blocked readers are woken, breaking fairness.
      @coroutine.pause()
      data
    }
    None => {
      let reader = @ref.new(Some(@coroutine.current_coroutine()))
      self.readers.push_back(reader)
      @coroutine.suspend() catch {
        err => {
          reader.val = None
          raise err
        }
      }
      continue self.buffer.pop_front()
    }
  }
}

///|
/// Try to fetch an element from the queue without blocking.
/// If no element is in the queue at the moment, `None` is returned.
pub fn[X] Queue::try_get(self : Queue[X]) -> X? {
  self.buffer.pop_front()
}
