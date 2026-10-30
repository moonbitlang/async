// Copyright 2026 International Digital Economy Academy
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
test "pending resize does not leak between event loops" {
  assert_true(resize_state.val is None)
  for _ in 0..<2 {
    with_event_loop(() => {
      guard resize_state.val is Some(resize) else {
        fail("resize state should be initialized")
      }
      assert_false(resize.pending)
      resize.pending = true
    })
    assert_true(resize_state.val is None)
  }
}
