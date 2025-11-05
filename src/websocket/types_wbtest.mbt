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
  assert_eq(CloseCode::UnsupportedData.to_int(), 1003)
  assert_eq(CloseCode::InvalidFramePayload.to_int(), 1007)
  assert_eq(CloseCode::PolicyViolation.to_int(), 1008)
  assert_eq(CloseCode::MessageTooBig.to_int(), 1009)
  assert_eq(CloseCode::InternalError.to_int(), 1011)
  assert_eq(CloseCode::from_int(1000), Some(CloseCode::Normal))
  assert_eq(CloseCode::from_int(1001), Some(CloseCode::GoingAway))
  assert_eq(CloseCode::from_int(1002), Some(CloseCode::ProtocolError))
  assert_eq(CloseCode::from_int(1003), Some(CloseCode::UnsupportedData))
  assert_eq(CloseCode::from_int(1007), Some(CloseCode::InvalidFramePayload))
  assert_eq(CloseCode::from_int(1008), Some(CloseCode::PolicyViolation))
  assert_eq(CloseCode::from_int(1009), Some(CloseCode::MessageTooBig))
  assert_eq(CloseCode::from_int(1011), Some(CloseCode::InternalError))

  // Invalid codes
  assert_eq(CloseCode::from_int(999), None)
  assert_eq(CloseCode::from_int(9999), None)
}

///|
test "Message structure" {
  let text_msg = Message::Text("hello")
  match text_msg {
    Message::Text(content) => assert_eq(content, "hello")
    Message::Binary(_) => abort("Expected Text message")
  }
  let binary_data = Bytes::make(5, 42)
  let binary_msg = Message::Binary(binary_data)
  match binary_msg {
    Message::Binary(data) => {
      assert_eq(data.length(), 5)
      assert_eq(data[0], 42)
    }
    Message::Text(_) => abort("Expected Binary message")
  }
}
