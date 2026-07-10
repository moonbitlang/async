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
pub(all) enum Encoding {
  UTF8
}

///|
pub(open) trait Writer {
  /// `write_once` may accept fewer than `len` bytes, but it must make progress:
  /// for a non-empty request, its return value must be in `1..=len`.
  async fn write_once(Self, Bytes, offset~ : Int, len~ : Int) -> Int
  async fn write(Self, BytesView) -> Unit = _
  async fn write_text(Self, StringView) -> Unit = _
  async fn write_json(Self, Json) -> Unit = _
  async fn write_reader(Self, &Reader) -> Unit = _
}

///|
impl Writer with fn write(self, data) {
  let start = data.start_offset()
  let len = data.length()
  guard len > 0 else { return }
  let end = start + len
  for offset = start; offset < end; {
    let remaining = end - offset
    let progress = self.write_once(data.data(), offset~, len=remaining)
    guard progress > 0 && progress <= remaining else {
      abort("Writer::write_once returned an invalid byte count")
    }
    continue offset + progress
  }
}

///|
/// Encode `text` as UTF-8 and write all encoded bytes.
impl Writer with fn write_text(self, text) {
  self.write(@utf8.encode(text))
}

///|
/// Serialize `value` as JSON and write its UTF-8 representation.
impl Writer with fn write_json(self, value) {
  self.write_text(value.stringify())
}

///|
impl Writer with fn write_reader(self, reader) {
  let buf = reader._get_internal_buffer()
  if buf.len > 0 {
    let buf_bytes = buf.buf.unsafe_reinterpret_as_bytes()
    self.write(buf_bytes[buf.start:buf.start + buf.len])
    buf.start = 0
    buf.len = 0
  }
  buf.0.enlarge_to(1)
  let max_len = buf.buf.length()
  while reader._direct_read(buf.buf, offset=0, max_len~) is n && n > 0 {
    let buf_bytes = buf.buf.unsafe_reinterpret_as_bytes()
    self.write(buf_bytes[:n])
  }
}
