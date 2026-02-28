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
/// Flow control window for HTTP/2.
/// Maps flow control directly to coroutine suspension — no busy waiting.
struct FlowWindow {
  mut size : Int
  cond : @cond_var.Cond
}

///|
/// Create a new flow control window.
fn FlowWindow::new(initial_size : Int) -> FlowWindow {
  { size: initial_size, cond: @cond_var.Cond::new() }
}

///|
/// Consume bytes from the flow window.
/// If the window is exhausted (size <= 0), suspends the coroutine
/// until a WINDOW_UPDATE arrives.
/// Returns the number of bytes actually consumed (min of n and available).
async fn FlowWindow::consume(self : FlowWindow, n : Int) -> Int {
  while self.size <= 0 {
    self.cond.wait()
  }
  let consumed = @cmp.minimum(n, self.size)
  self.size = self.size - consumed
  consumed
}

///|
/// Update the flow window by incrementing its size.
/// Wakes any blocked senders.
fn FlowWindow::update(self : FlowWindow, increment : Int) -> Unit {
  self.size = self.size + increment
  if self.size > 0 {
    self.cond.broadcast()
  }
}
