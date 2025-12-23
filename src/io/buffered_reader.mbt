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
/// This type is for internal use only,
/// end users should not use this type directly.
#internal(internal, "this type is for internal use only")
struct ReaderBuffer(@io_buffer.Buffer)

///|
#internal(internal, "this function is for internal use only")
pub fn ReaderBuffer::new() -> ReaderBuffer {
  @io_buffer.new(0)
}

///|
async fn[R : Reader] ReaderBuffer::try_ensure(
  self : Self,
  len : Int,
  reader~ : R,
) -> Bool {
  if self.len >= len {
    return true
  }
  self.0.enlarge_to(len)
  let capacity = self.buf.length()
  while self.len < len {
    let offset = self.start + self.len
    let n = reader._direct_read(self.buf, offset~, max_len=capacity - offset)
    if n == 0 {
      return false
    }
    self.len += n
  } else {
    true
  }
}

///|
async fn[R : Reader] ReaderBuffer::find_opt(
  self : Self,
  target : Bytes,
  reader~ : R,
) -> Int? {
  let target_len = target.length()
  for searched = 0 {
    guard self.try_ensure(searched + target_len, reader~) else { return None }
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
/// A buffered wrapper around a normal reader.
/// This reader will buffer already read content,
/// and supports searching & arbitrary slicing of read content.
#deprecated("readers are now always buffered", skip_current_package=true)
struct BufferedReader[R](R)

///|
/// Create a new buffered reader that wrap around an existing reader.
pub fn[R] BufferedReader::new(reader : R) -> BufferedReader[R] {
  reader
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
  self._get_internal_buffer().try_ensure(len, reader=self.0)
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
  ignore(Reader::drop(self, n))
}

///|
pub impl[R : Reader] Reader for BufferedReader[R] with _get_internal_buffer(
  self,
) {
  self.0._get_internal_buffer()
}

///|
pub impl[R : Reader] Reader for BufferedReader[R] with _direct_read(
  self,
  dst,
  offset~,
  max_len~,
) {
  self.0._direct_read(dst, offset~, max_len~)
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
  let buf = self.0._get_internal_buffer()
  buf.buf[buf.start + index]
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
  let buf = self.0._get_internal_buffer()
  buf.buf.unsafe_reinterpret_as_bytes()[buf.start + start:buf.start + end]
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
  self.0._get_internal_buffer().find_opt(target, reader=self.0)
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
  self.read_until("\n")
}
