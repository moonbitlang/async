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
/// 
/// This reader buffers already read content and supports advanced operations like:
/// - Searching for byte patterns within buffered data
/// - Arbitrary slicing of read content without advancing the stream
/// - Indexed access to buffered data
/// - Line-by-line reading
///
/// ## Performance Considerations
///
/// `BufferedReader` is designed for scenarios where you need to:
/// - Look ahead in the data stream
/// - Search for patterns before consuming data
/// - Parse structured data that requires backtracking
///
/// For simple sequential reading, a plain `Reader` may be more efficient.
///
/// ## Memory Management
///
/// The buffer grows dynamically as needed. Call `drop()` periodically
/// to reduce memory usage by removing consumed data from the buffer.
struct BufferedReader[R] {
  reader : R
  mut buf : FixedArray[Byte]
  mut start : Int
  mut len : Int
}

///|
/// Default segment size for buffer allocation (1024 bytes).
/// 
/// The buffer grows in multiples of this size to balance
/// memory usage and allocation efficiency.
const SEGMENT_SIZE = 1024

///|
/// Create a new buffered reader that wraps around an existing reader.
///
/// The buffer starts with a default size of `SEGMENT_SIZE` bytes
/// and grows automatically as needed.
///
/// # Parameters
/// - `reader`: The underlying reader to wrap
///
/// # Returns
/// A new `BufferedReader` instance
pub fn[R] BufferedReader::new(reader : R) -> BufferedReader[R] {
  { reader, buf: FixedArray::make(SEGMENT_SIZE, 0), start: 0, len: 0 }
}

///|
/// Enlarge the internal buffer to accommodate at least `n` bytes.
/// 
/// This method handles buffer management by either shifting existing
/// data or allocating a larger buffer as needed.
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
/// Ensure that at least `len` bytes are available in the buffer.
/// 
/// This method reads from the underlying reader as needed to satisfy
/// the requirement. If the underlying reader reaches EOF before
/// enough data is available, `ReaderClosed` is raised.
async fn[R : Reader] BufferedReader::ensure(self : Self[R], len : Int) -> Unit {
  if self.len >= len {
    return
  }
  self.enlarge_to(len)
  while self.len < len {
    let n = self.reader.read(
      self.buf,
      offset=self.start + self.len,
      max_len=len - self.len,
    )
    if n == 0 {
      raise ReaderClosed
    }
    self.len += n
  }
}

///|
/// Fetch additional data from the underlying reader.
/// 
/// This method attempts to read more data into the buffer.
/// The exact amount fetched may vary based on what the underlying
/// reader provides.
///
/// # Returns
/// `true` if data was successfully fetched, `false` if the
/// underlying reader has reached EOF
async fn[R : Reader] BufferedReader::fetch_more(self : Self[R]) -> Bool {
  self.enlarge_to(self.len + SEGMENT_SIZE)
  let offset = self.start + self.len
  let n = self.reader.read(
    self.buf,
    offset~,
    max_len=self.buf.length() - offset,
  )
  self.len += n
  n > 0
}

///|
/// Drop the first `n` bytes of data from the reader.
/// 
/// This operation advances the reader stream and affects the semantics
/// of all index-based operations. If there isn't enough buffered data,
/// the method will request more data from the inner reader.
///
/// # Parameters
/// - `n`: Number of bytes to drop
///
/// # Errors
/// Raises `ReaderClosed` if the inner reader reaches EOF before
/// enough data is available to drop.
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
/// Implementation of the `Reader` trait for `BufferedReader`.
/// 
/// This method reads data from the buffer if available, otherwise
/// delegates to the underlying reader. Copied data is removed
/// from the reader stream.
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
/// Get the nth byte from the start of the reader stream.
/// 
/// This operation is idempotent and does not advance the reader stream.
/// If there isn't enough buffered data, the method will request more
/// data from the inner reader.
///
/// # Parameters
/// - `index`: Zero-based index of the byte to retrieve
///
/// # Returns
/// The byte at the specified index
///
/// # Errors
/// Raises `ReaderClosed` if the inner reader reaches EOF before
/// the indexed byte is available.
pub async fn[R : Reader] BufferedReader::op_get(
  self : Self[R],
  index : Int,
) -> Byte {
  self.ensure(index + 1)
  self.buf[self.start + index]
}

///|
/// Get a slice of data from the reader as a `BytesView`.
/// 
/// This operation is idempotent and does not advance the reader stream.
/// If there isn't enough buffered data, the method will request more
/// data from the inner reader.
///
/// # Parameters
/// - `start`: Starting index (default: 0)
/// - `end`: Ending index (exclusive)
///
/// # Returns
/// A `BytesView` containing the requested slice
///
/// # Errors
/// Raises `ReaderClosed` if the inner reader reaches EOF before
/// the requested slice is available.
///
/// # Safety
/// The returned `BytesView` is temporary and MUST NOT be used after
/// calling methods that consume data from the reader (like `drop()` or `read()`).
/// Copy the view with `.to_bytes()` before consuming data if you need
/// to retain the data.
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
/// Find the first occurrence of a byte pattern in the buffered data.
/// 
/// This operation is idempotent and does not advance the reader stream.
/// If the pattern is not found in currently buffered data, the method
/// will request more data from the inner reader.
///
/// # Parameters
/// - `target`: The byte pattern to search for
///
/// # Returns
/// The index of the first occurrence of the pattern, counted from
/// the start of the reader stream
///
/// # Errors
/// Raises `ReaderClosed` if the inner reader reaches EOF before
/// the target pattern is found.
pub async fn[R : Reader] BufferedReader::find(
  self : Self[R],
  target : Bytes,
) -> Int {
  for searched = self.start {
    let len = self.len
    let end = self.start + len
    let region = self.buf.unsafe_reinterpret_as_bytes()[searched:end]
    if region.find(target) is Some(i) {
      return searched + i - self.start
    }
    if !self.fetch_more() {
      raise ReaderClosed
    }
    continue self.start + len
  }
}

///|
/// Find the first occurrence of a byte pattern, returning `None` if not found.
/// 
/// This operation is idempotent and does not advance the reader stream.
/// If the pattern is not found in currently buffered data, the method
/// will request more data from the inner reader. Unlike `find()`, this
/// method returns `None` if the pattern is not found when EOF is reached.
///
/// # Parameters
/// - `target`: The byte pattern to search for
///
/// # Returns
/// `Some(index)` if the pattern is found, `None` if EOF is reached
/// without finding the pattern
pub async fn[R : Reader] BufferedReader::find_opt(
  self : Self[R],
  target : Bytes,
) -> Int? {
  for searched = self.start {
    let len = self.len
    let end = self.start + len
    let region = self.buf.unsafe_reinterpret_as_bytes()[searched:end]
    if region.find(target) is Some(i) {
      return Some(searched + i - self.start)
    }
    if !self.fetch_more() {
      return None
    }
    continue self.start + len
  }
}

///|
/// Read a line of text from the buffered reader.
/// 
/// This method reads content until a newline character (`\n`) is found.
/// The returned string excludes the trailing newline, but the newline
/// character is consumed from the reader.
///
/// # Returns
/// - `Some(line)` if a line is successfully read
/// - `None` if the reader has reached EOF with no data
///
/// # Behavior
/// - If a newline is found, returns the line content (without newline)
/// - If EOF is reached with data but no newline, returns all remaining data
/// - If EOF is reached with no data, returns `None`
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
