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

/// Tests for public WebSocket API

///|
test "CloseCode conversions" {
  assert_eq(CloseCode::Normal.to_int(), 1000)
  assert_eq(CloseCode::GoingAway.to_int(), 1001)
  assert_eq(CloseCode::ProtocolError.to_int(), 1002)
  assert_eq(CloseCode::from_int(1000), Some(CloseCode::Normal))
  assert_eq(CloseCode::from_int(1001), Some(CloseCode::GoingAway))
  assert_eq(CloseCode::from_int(1002), Some(CloseCode::ProtocolError))

  // Invalid code
  assert_eq(CloseCode::from_int(9999), None)
}
