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
/// HTTP/2 settings per RFC 7540 Section 6.5.
priv struct H2Settings {
  mut header_table_size : Int
  mut enable_push : Bool
  mut max_concurrent_streams : Int
  mut initial_window_size : Int
  mut max_frame_size : Int
  mut max_header_list_size : Int
}

// Settings identifiers

///|
let settings_header_table_size : Int = 0x1

///|
let settings_enable_push : Int = 0x2

///|
let settings_max_concurrent_streams : Int = 0x3

///|
let settings_initial_window_size : Int = 0x4

///|
let settings_max_frame_size : Int = 0x5

///|
let settings_max_header_list_size : Int = 0x6

///|
/// Create default HTTP/2 settings.
fn H2Settings::default() -> H2Settings {
  {
    header_table_size: default_header_table_size,
    enable_push: true,
    max_concurrent_streams: 100,
    initial_window_size: default_initial_window_size,
    max_frame_size: default_max_frame_size,
    max_header_list_size: default_max_header_list_size,
  }
}

///|
/// Encode settings into payload bytes for a SETTINGS frame.
fn H2Settings::encode(self : H2Settings) -> Bytes {
  let buf = @buffer.new()
  fn write_setting(id : Int, value : Int) {
    buf.write_int16_be(Int16::from_int(id))
    buf.write_int_be(value)
  }
  write_setting(settings_header_table_size, self.header_table_size)
  write_setting(settings_enable_push, if self.enable_push { 1 } else { 0 })
  write_setting(settings_max_concurrent_streams, self.max_concurrent_streams)
  write_setting(settings_initial_window_size, self.initial_window_size)
  write_setting(settings_max_frame_size, self.max_frame_size)
  write_setting(settings_max_header_list_size, self.max_header_list_size)
  buf.to_bytes()
}

///|
/// Apply settings from a SETTINGS frame payload.
fn H2Settings::apply(self : H2Settings, payload : Bytes) -> Unit raise {
  if payload.length() % 6 != 0 {
    raise H2Error(FrameSizeError, "SETTINGS payload not a multiple of 6")
  }
  let mut pos = 0
  while pos + 6 <= payload.length() {
    let id = (payload[pos].to_int() << 8) | payload[pos + 1].to_int()
    let value = (payload[pos + 2].to_int() << 24) |
      (payload[pos + 3].to_int() << 16) |
      (payload[pos + 4].to_int() << 8) |
      payload[pos + 5].to_int()
    match id {
      _ if id == settings_header_table_size => self.header_table_size = value
      _ if id == settings_enable_push => self.enable_push = value != 0
      _ if id == settings_max_concurrent_streams =>
        self.max_concurrent_streams = value
      _ if id == settings_initial_window_size => {
        if value > 0x7fffffff {
          raise H2Error(FlowControlError, "INITIAL_WINDOW_SIZE exceeds maximum")
        }
        self.initial_window_size = value
      }
      _ if id == settings_max_frame_size => {
        if value < 16384 || value > 16777215 {
          raise H2Error(ProtocolError, "MAX_FRAME_SIZE out of range")
        }
        self.max_frame_size = value
      }
      _ if id == settings_max_header_list_size =>
        self.max_header_list_size = value
      _ => () // Unknown settings identifiers MUST be ignored (RFC 7540 Section 6.5.2)
    }
    pos = pos + 6
  }
}
