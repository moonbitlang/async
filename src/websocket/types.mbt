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
/// WebSocket opcode types - internal implementation detail
priv enum OpCode {
  Continuation // 0x0
  Text // 0x1
  Binary // 0x2
  Close // 0x8
  Ping // 0x9
  Pong // 0xA
}

///|
fn OpCode::to_byte(self : OpCode) -> Byte {
  match self {
    Continuation => b'\x00'
    Text => b'\x01'
    Binary => b'\x02'
    Close => b'\x08'
    Ping => b'\x09'
    Pong => b'\x0A'
  }
}

///|
fn OpCode::from_byte(byte : Byte) -> OpCode raise FrameError {
  match byte {
    b'\x00' => Continuation
    b'\x01' => Text
    b'\x02' => Binary
    b'\x08' => Close
    b'\x09' => Ping
    b'\x0A' => Pong
    _ => raise FrameError
  }
}

///|
/// WebSocket frame - internal implementation detail
priv struct Frame {
  fin : Bool
  opcode : OpCode
  payload : Bytes
}

///|
/// WebSocket message
pub(all) enum Message {
  Binary(BytesView)
  Text(StringView)
} derive(Show)

///|
/// WebSocket close status codes
pub(all) enum CloseCode {
  Normal // 1000
  GoingAway // 1001
  ProtocolError // 1002
  UnsupportedData // 1003
  Abnormal // 1006
  InvalidFramePayload // 1007
  PolicyViolation // 1008
  MessageTooBig // 1009
  InternalError // 1011
} derive(Show, Eq)

///|
fn CloseCode::to_int(self : CloseCode) -> Int {
  match self {
    Normal => 1000
    GoingAway => 1001
    ProtocolError => 1002
    UnsupportedData => 1003
    Abnormal => 1006
    InvalidFramePayload => 1007
    PolicyViolation => 1008
    MessageTooBig => 1009
    InternalError => 1011
  }
}

///|
fn CloseCode::from_int(code : Int) -> CloseCode raise FrameError {
  match code {
    1000 => Normal
    1001 => GoingAway
    1002 => ProtocolError
    1003 => UnsupportedData
    1006 => Abnormal
    1007 => InvalidFramePayload
    1008 => PolicyViolation
    1009 => MessageTooBig
    1011 => InternalError
    _ => raise FrameError
  }
}

///|
pub suberror WebSocketError {
  ConnectionClosed(CloseCode) // Connection was closed
  InvalidHandshake(String) // Handshake failed with specific reason
} derive(Show)

///|
priv suberror FrameError
