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
/// A buffered writer with a fixed-size buffer that wraps around a normal writer.
/// 
/// Data is buffered instead of being committed to the underlying writer immediately,
/// unless the buffer is full or an explicit flush is requested. Buffering can
/// significantly improve performance for scenarios where small writes are expensive,
/// such as network connections or disk I/O.
///
/// ## Usage
///
/// Always remember to call `flush()` before writing directly to the underlying writer
/// or before the buffered writer goes out of scope. Otherwise, some data may remain
/// uncommitted in the buffer.
///
/// ## Performance Benefits
///
/// - Reduces the number of system calls by batching small writes
/// - Improves throughput for high-frequency write operations
/// - Particularly beneficial for network I/O and file operations
struct BufferedWriter[W] {
  writer : W
  buf : FixedArray[Byte]
  mut len : Int
}

///|
/// Create a buffered writer with a specified buffer size.
///
/// The buffer size determines how much data can be accumulated before
/// automatic flushing occurs. Larger buffers reduce the frequency of
/// writes to the underlying writer but use more memory.
///
/// # Parameters
/// - `writer`: The underlying writer to wrap
/// - `size`: Buffer size in bytes (default: 1024)
///
/// # Returns
/// A new `BufferedWriter` instance
pub fn[W] BufferedWriter::new(
  writer : W,
  size? : Int = 1024,
) -> BufferedWriter[W] {
  { writer, buf: FixedArray::make(size, 0), len: 0 }
}

///|
/// Get the internal buffer capacity of the buffered writer.
///
/// This returns the maximum number of bytes that can be buffered
/// before an automatic flush occurs.
///
/// # Returns
/// The buffer capacity in bytes
pub fn[W] BufferedWriter::capacity(self : BufferedWriter[W]) -> Int {
  self.buf.length()
}

///|
/// Flush all buffered data to the underlying writer.
///
/// This method commits all data currently in the buffer to the underlying
/// writer and resets the buffer. It should be called:
/// - Before writing directly to the underlying writer
/// - When you need to ensure data is committed (e.g., before program exit)
/// - At logical boundaries in your application (e.g., end of a response)
pub async fn[W : Writer] BufferedWriter::flush(
  self : BufferedWriter[W],
) -> Unit {
  if self.len > 0 {
    self.writer.write(self.buf.unsafe_reinterpret_as_bytes()[:self.len])
    self.len = 0
  }
}

///|
/// Implementation of `Writer::write_once` for `BufferedWriter`.
/// 
/// This method adds data to the internal buffer. If the buffer becomes
/// full, it automatically flushes before adding new data.
pub impl[W : Writer] Writer for BufferedWriter[W] with write_once(
  self,
  buf,
  offset~,
  len~,
) {
  if self.len >= self.buf.length() {
    self.flush()
  }
  let len = @cmp.minimum(len, self.buf.length() - self.len)
  self.buf.blit_from_bytes(self.len, buf, offset, len)
  self.len += len
  len
}

///|
/// Implementation of `Writer::write_reader` for `BufferedWriter`.
/// 
/// This method efficiently streams data from a reader through the buffer
/// to the underlying writer, automatically flushing when the buffer fills.
pub impl[W : Writer] Writer for BufferedWriter[W] with write_reader(
  self,
  reader,
) {
  for {
    if self.len >= self.buf.length() {
      self.flush()
    }
    let n = reader.read(
      self.buf,
      offset=self.len,
      max_len=self.buf.length() - self.len,
    )
    if n == 0 {
      break
    }
    self.len += n
  }
}
