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

/// Internal structure representing a reader waiting for data from the queue.
/// This is used internally by the Queue implementation to manage blocked readers.
priv struct Reader[X] {
  /// The value provided to the reader.
  /// `value` must be `Some(_)` when the reader is woken
  mut value : X?
  /// The coroutine associated with this reader.
  /// `None` indicates that the reader is cancelled
  mut coro : @coroutine.Coroutine?
}

/// An asynchronous queue that allows readers to wait for data to arrive
/// in a non-blocking manner.
/// 
/// The internal buffer size of this queue is unlimited,
/// and writing to the queue will never block.
/// 
/// # Features
/// - Non-blocking writes: `put` operations never block
/// - Blocking reads: `get` operations block until data is available  
/// - Fair scheduling: Multiple readers are served in FIFO order
/// - Cancellation support: Blocked readers can be cancelled
/// - Try-read support: `try_get` provides non-blocking read option
struct Queue[X] {
  /// Queue of readers waiting for data
  readers : @deque.Deque[Reader[X]]
  /// Internal buffer for storing queued elements
  /// Invariant: if `buffer` is non-empty, `readers` must be empty
  buffer : @deque.Deque[X]
}

/// Create an empty asynchronous queue.
/// 
/// # Returns
/// A new empty Queue that can hold elements of type X.
/// 
/// # Example
/// ```moonbit
/// let queue : @aqueue.Queue[Int] = @aqueue.Queue::new()
/// ```
#as_free_fn
pub fn[X] Queue::new() -> Queue[X] {
  { readers: @deque.new(), buffer: @deque.new() }
}

/// Put a new element into the queue. This function never blocks.
/// 
/// If the queue is currently empty and there are readers blocked waiting for data,
/// one reader will be woken to process the data immediately.
/// Otherwise, the data is stored in the internal buffer.
/// 
/// # Parameters
/// - `data`: The element to add to the queue
/// 
/// # Example
/// ```moonbit
/// let queue : @aqueue.Queue[Int] = @aqueue.Queue::new()
/// queue.put(42)
/// queue.put(100)
/// ```
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

/// Fetch an element from the queue asynchronously.
/// 
/// If the queue is currently empty, `get` will block and wait until data arrives.
/// If there are multiple readers blocked on `get`, new data will be delivered 
/// in a first-come-first-serve manner.
/// 
/// # Returns
/// The next available element from the queue.
/// 
/// # Cancellation
/// `get` itself never fails and will wait indefinitely for data.
/// However, since `get` is a blocking point, the task running `get` may be cancelled.
/// In this case, a cancellation error will be raised from `get`.
pub async fn[X] Queue::get(self : Queue[X]) -> X {
  if self.buffer.pop_front() is Some(data) {
    return data
  }
  let reader = { value: None, coro: Some(@coroutine.current_coroutine()) }
  self.readers.push_back(reader)
  @coroutine.suspend() catch {
    err => {
      reader.coro = None
      raise err
    }
  }
  reader.value.unwrap()
}

/// Try to fetch an element from the queue without blocking.
/// 
/// This is the non-blocking variant of `get`. If no element is available 
/// in the queue at the moment, `None` is returned immediately.
/// 
/// # Returns
/// - `Some(data)` if an element is available
/// - `None` if the queue is empty
/// 
/// # Example
/// ```moonbit
/// let queue : @aqueue.Queue[Int] = @aqueue.Queue::new()
/// inspect(queue.try_get(), content="None")
/// queue.put(42)
/// inspect(queue.try_get(), content="Some(42)")
/// ```
pub fn[X] Queue::try_get(self : Queue[X]) -> X? {
  self.buffer.pop_front()
}
