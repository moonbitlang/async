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
fn OpCode::from_byte(byte : Byte) -> OpCode? {
  match byte {
    b'\x00' => Some(Continuation)
    b'\x01' => Some(Text)
    b'\x02' => Some(Binary)
    b'\x08' => Some(Close)
    b'\x09' => Some(Ping)
    b'\x0A' => Some(Pong)
    _ => None
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
fn CloseCode::from_int(code : Int) -> CloseCode? {
  match code {
    1000 => Some(Normal)
    1001 => Some(GoingAway)
    1002 => Some(ProtocolError)
    1003 => Some(UnsupportedData)
    1006 => Some(Abnormal)
    1007 => Some(InvalidFramePayload)
    1008 => Some(PolicyViolation)
    1009 => Some(MessageTooBig)
    1011 => Some(InternalError)
    _ => None
  }
}

///|
pub suberror WebSocketError {
  ConnectionClosed(CloseCode) // Connection was closed
  InvalidHandshake(String) // Handshake failed with specific reason
  FrameError(String) // Malformed frame with details
} derive(Show)
