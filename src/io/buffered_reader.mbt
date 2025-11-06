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
/// A buffered wrapper around a normal reader.
/// This reader will buffer already read content,
/// and supports searching & arbitrary slicing of read content.
struct BufferedReader[R] {
  reader : R
  mut buf : FixedArray[Byte]
  mut start : Int
  mut len : Int
}

///|
const SEGMENT_SIZE = 1024

///|
/// Create a new buffered reader that wrap around an existing reader.
pub fn[R] BufferedReader::new(reader : R) -> BufferedReader[R] {
  { reader, buf: FixedArray::make(SEGMENT_SIZE, 0), start: 0, len: 0 }
}

///|
fn[R] BufferedReader::enlarge_to(self : Self[R], n : Int) -> Unit {
  let capacity = self.buf.length()
  if self.start + n <= capacity {
    return
  }
  if n <= capacity {
    self.buf.blit_to(self.buf, src_offset=self.start, len=self.len)
    self.start = 0
    return
  }
  let padding = n % SEGMENT_SIZE
  let target_len = if padding == 0 { n } else { n - padding + SEGMENT_SIZE }
  let new_buf = FixedArray::make(target_len, b'0')
  self.buf.blit_to(new_buf, src_offset=self.start, dst_offset=0, len=self.len)
  self.buf = new_buf
  self.start = 0
}

///|
/// Make sure at least `len` bytes of data are buffered,
/// read from the underlying reader if necessary.
/// The actual amount of data fetched may be larger than `len`.
/// Returns `true` if data are successfully fetched,
/// or `false` if the underlying reader already reached EOF.
async fn[R : Reader] BufferedReader::try_ensure(
  self : Self[R],
  len : Int,
) -> Bool {
  if self.len >= len {
    return true
  }
  self.enlarge_to(len)
  while self.len < len {
    let n = self.reader.read(self.buf, offset=self.start + self.len)
    if n == 0 {
      return false
    }
    self.len += n
  } else {
    true
  }
}

///|
async fn[R : Reader] BufferedReader::ensure(self : Self[R], len : Int) -> Unit {
  if !self.try_ensure(len) {
    raise ReaderClosed
  }
}

///|
/// `reader.drop(n)` drops the first `n` bytes of data in the reader.
/// If there are no enough data to drop,
/// `BufferedReader` will request more data from the inner reader.
/// If the inner reader is closed before enough data is available,
/// `ReaderClosed` will be raised.
///
/// This operation will advance the reader stream,
/// and will affect the semantic of all index based operations.
pub async fn[R : Reader] BufferedReader::drop(self : Self[R], n : Int) -> Unit {
  self.ensure(n)
  self.len -= n
  if self.len == 0 {
    self.start = 0
  } else {
    self.start += n
  }
}

///|
/// Copy some data into the given buffer from the reader.
/// If there is no buffered data,
/// `BufferedReader` will request more data from the inner reader.
/// The number of read bytes will be returned, which is always positive,
/// unless the stream already reaches its end,
/// i.e. there are no buffered data and the inner reader has been closed.
/// Copied data will be removed from the reader stream.
pub impl[R : Reader] Reader for BufferedReader[R] with read(
  self,
  buf,
  offset? = 0,
  max_len? = buf.length() - offset,
) {
  if self.len > 0 {
    let n = @cmp.minimum(max_len, self.len)
    self.buf.blit_to(buf, src_offset=self.start, dst_offset=offset, len=n)
    self.drop(n)
    n
  } else {
    self.reader.read(buf, offset~, max_len~)
  }
}

///|
/// Get the nth byte from the start of the reader.
/// If there are no enough data available,
/// `BufferedReader` will request more data from the inner reader.
/// If the inner reader is closed before enough data is available,
/// `ReaderClosed` will be raised.
/// `op_get` will not advance the reader stream,
/// so this operation is idempotent.
pub async fn[R : Reader] BufferedReader::op_get(
  self : Self[R],
  index : Int,
) -> Byte {
  self.ensure(index + 1)
  self.buf[self.start + index]
}

///|
/// Get a slice of data from the reader,
/// `start` and `end` count from start of stream.
/// If there are no enough data available,
/// `BufferedReader` will request more data from the inner reader.
/// If the inner reader is closed before enough data is available,
/// `ReaderClosed` will be raised.
///
/// `op_as_view` will not advance the reader stream,
/// so this operation is idempotent.
///
/// The returned bytes view MUST be temporary.
/// If data is consumed (for example via `.drop()` or `.read()`)
/// from the reader after `op_as_view`, the view MUST NOT be used again.
/// The view should be copied via `.to_bytes()`
/// before consuming data from the reader.
pub async fn[R : Reader] BufferedReader::op_as_view(
  self : Self[R],
  start? : Int = 0,
  end~ : Int,
) -> BytesView {
  if start == end {
    return ""
  }
  guard start < end
  self.ensure(end)
  self.buf.unsafe_reinterpret_as_bytes()[self.start + start:self.start + end]
}

///|
/// Find the start index of the first occurence of `bytes` in the reader.
/// The returned index is counted from start of reader.
///
/// If the target substring is not found in buffered data,
/// `BufferedReader` will request more data from the inner reader.
///
/// If the inner reader is closed before the target substring is found,
/// `None` will be returned.
///
/// `find_opt` will not advance the reader stream,
/// so this operation is idempotent.
pub async fn[R : Reader] BufferedReader::find_opt(
  self : Self[R],
  target : Bytes,
) -> Int? {
  let target_len = target.length()
  for searched = 0 {
    guard self.try_ensure(searched + target_len) else { return None }
    let len = self.len
    let start = self.start + searched
    let end = self.start + len
    let region = self.buf.unsafe_reinterpret_as_bytes()[start:end]
    if region.find(target) is Some(i) {
      return Some(searched + i)
    }
    continue len - target_len + 1
  }
}

///|
/// Find the start index of the first occurence of `bytes` in the reader.
/// The returned index is counted from start of reader.
///
/// If the target substring is not found in buffered data,
/// `BufferedReader` will request more data from the inner reader.
///
/// If the inner reader is closed before the target substring is found,
/// `ReaderClosed` will be raised.
///
/// `find` will not advance the reader stream,
/// so this operation is idempotent.
pub async fn[R : Reader] BufferedReader::find(
  self : Self[R],
  target : Bytes,
) -> Int {
  match self.find_opt(target) {
    None => raise ReaderClosed
    Some(index) => index
  }
}

///|
/// Read content from a buffered reader until newline (`\n`).
/// If the reader already reaches EOF, `None` is returned.
/// Otherwise, the content of the line (without the trailing newline) is returned,
/// and the content of the line and the newline character
/// will be conusmed from the reader.
/// The returned string is decoded with UTF8.
pub async fn[R : Reader] BufferedReader::read_line(self : Self[R]) -> String? {
  match self.find_opt("\n") {
    None if self.len == 0 => None
    None => Some(self.read_all().text())
    Some(newline_index) => {
      let line = @encoding/utf8.decode(self[:newline_index])
      self.drop(newline_index + 1)
      Some(line)
    }
  }
}
