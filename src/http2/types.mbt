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
/// HTTP/2 frame types per RFC 7540 Section 6.
pub(all) enum FrameType {
  Data
  Headers
  Priority
  RstStream
  Settings
  PushPromise
  Ping
  GoAway
  WindowUpdate
  Continuation
  Unknown(Byte)
} derive(Show, Eq)

///|
fn FrameType::from_byte(b : Byte) -> FrameType {
  match b.to_int() {
    0x0 => Data
    0x1 => Headers
    0x2 => Priority
    0x3 => RstStream
    0x4 => Settings
    0x5 => PushPromise
    0x6 => Ping
    0x7 => GoAway
    0x8 => WindowUpdate
    0x9 => Continuation
    _ => Unknown(b)
  }
}

///|
fn FrameType::to_byte(self : FrameType) -> Byte {
  match self {
    Data => b'\x00'
    Headers => b'\x01'
    Priority => b'\x02'
    RstStream => b'\x03'
    Settings => b'\x04'
    PushPromise => b'\x05'
    Ping => b'\x06'
    GoAway => b'\x07'
    WindowUpdate => b'\x08'
    Continuation => b'\x09'
    Unknown(b) => b
  }
}

///|
/// HTTP/2 error codes per RFC 7540 Section 7.
pub(all) enum H2ErrorCode {
  NoError
  ProtocolError
  InternalError
  FlowControlError
  SettingsTimeout
  StreamClosed
  FrameSizeError
  RefusedStream
  Cancel
  CompressionError
  ConnectError
  EnhanceYourCalm
  InadequateSecurity
  Http11Required
} derive(Show, Eq, ToJson)

///|
fn H2ErrorCode::from_int(code : Int) -> H2ErrorCode {
  match code {
    0x0 => NoError
    0x1 => ProtocolError
    0x2 => InternalError
    0x3 => FlowControlError
    0x4 => SettingsTimeout
    0x5 => StreamClosed
    0x6 => FrameSizeError
    0x7 => RefusedStream
    0x8 => Cancel
    0x9 => CompressionError
    0xa => ConnectError
    0xb => EnhanceYourCalm
    0xc => InadequateSecurity
    0xd => Http11Required
    _ => ProtocolError
  }
}

///|
fn H2ErrorCode::to_int(self : H2ErrorCode) -> Int {
  match self {
    NoError => 0x0
    ProtocolError => 0x1
    InternalError => 0x2
    FlowControlError => 0x3
    SettingsTimeout => 0x4
    StreamClosed => 0x5
    FrameSizeError => 0x6
    RefusedStream => 0x7
    Cancel => 0x8
    CompressionError => 0x9
    ConnectError => 0xa
    EnhanceYourCalm => 0xb
    InadequateSecurity => 0xc
    Http11Required => 0xd
  }
}

///|
/// HTTP/2 stream states per RFC 7540 Section 5.1.
pub(all) enum StreamState {
  Idle
  ReservedLocal
  ReservedRemote
  Open
  HalfClosedLocal
  HalfClosedRemote
  Closed
} derive(Show, Eq)

///|
/// HTTP/2 frame header (9 bytes on the wire).
pub(all) struct FrameHeader {
  length : Int
  frame_type : FrameType
  flags : Byte
  stream_id : Int
} derive(Show)

///|
/// HTTP/2 frame = header + payload.
pub(all) struct Frame {
  header : FrameHeader
  payload : Bytes
} derive(Show)

// Frame flag constants

///|
let flag_end_stream : Byte = b'\x01'

///|
let flag_ack : Byte = b'\x01'

///|
let flag_end_headers : Byte = b'\x04'

///|
let flag_padded : Byte = b'\x08'

///|
let flag_priority : Byte = b'\x20'

///|
/// HTTP/2 client connection preface magic string.
let client_preface : Bytes = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

// Default settings constants

///|
let default_header_table_size : Int = 4096

///|
let default_initial_window_size : Int = 65535

///|
let default_max_frame_size : Int = 16384

///|
let default_max_header_list_size : Int = 0x7fffffff

///|
/// HTTP/2 connection/stream error.
pub suberror H2Error {
  H2Error(H2ErrorCode, String)
} derive(Show, ToJson)

///|
/// Check if a flag is set.
fn has_flag(flags : Byte, flag : Byte) -> Bool {
  (flags.to_int() & flag.to_int()) != 0
}
