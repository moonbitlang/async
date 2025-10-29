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
test "OpCode conversions" {
  // Test OpCode to byte conversion
  assert_eq(OpCode::Text.to_byte(), b'\x01')
  assert_eq(OpCode::Binary.to_byte(), b'\x02')
  assert_eq(OpCode::Close.to_byte(), b'\x08')
  assert_eq(OpCode::Ping.to_byte(), b'\x09')
  assert_eq(OpCode::Pong.to_byte(), b'\x0A')

  // Test byte to OpCode conversion
  assert_eq(OpCode::from_byte(b'\x01'), Some(OpCode::Text))
  assert_eq(OpCode::from_byte(b'\x02'), Some(OpCode::Binary))
  assert_eq(OpCode::from_byte(b'\x08'), Some(OpCode::Close))
  assert_eq(OpCode::from_byte(b'\x09'), Some(OpCode::Ping))
  assert_eq(OpCode::from_byte(b'\x0A'), Some(OpCode::Pong))

  // Invalid opcode
  assert_eq(OpCode::from_byte(b'\xFF'), None)
}

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

///|
test "Frame structure" {
  let frame = Frame::{ fin: true, opcode: OpCode::Text, payload: b"Hello" }
  assert_eq(frame.fin, true)
  assert_eq(frame.opcode, OpCode::Text)
  assert_eq(frame.payload, b"Hello")
}

///|
test "Message structure" {
  let msg = Message::{ mtype: MessageType::Text, data: b"Test message" }
  assert_eq(msg.mtype, MessageType::Text)
  assert_eq(msg.data, b"Test message")
}
