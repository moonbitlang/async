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
/// Internal byte buffer with a sliding window.
///
/// `buf` stores the underlying bytes, `start` is the offset of the first valid
/// byte, and `len` is the number of valid bytes available. The buffer does not
/// enforce invariants beyond these fields; callers are responsible for keeping
/// them consistent.
pub(all) struct Buffer {
  mut buf : FixedArray[Byte]
  mut start : Int
  mut len : Int
}

///|
/// Create a new buffer with the given capacity.
///
/// The buffer starts empty (`start = 0`, `len = 0`).
///
/// # Example
/// ```mbt check
/// test "new buffer is empty" {
///   let buf = Buffer::new(8)
///   inspect(buf.buf.length(), content="8")
///   inspect(buf.start, content="0")
///   inspect(buf.len, content="0")
/// }
/// ```
#as_free_fn
pub fn Buffer::new(size : Int) -> Buffer {
  { buf: FixedArray::make(size, 0), start: 0, len: 0 }
}

///|
/// Clear the buffer and release its storage.
///
/// After `clear`, the buffer has zero capacity and no valid bytes.
///
/// # Example
/// ```mbt check
/// test "clear resets state" {
///   let buf = Buffer::new(4)
///   buf.start = 1
///   buf.len = 2
///   Buffer::clear(buf)
///   inspect(buf.buf.length(), content="0")
///   inspect(buf.start, content="0")
///   inspect(buf.len, content="0")
/// }
/// ```
pub fn Buffer::clear(buf : Buffer) -> Unit {
  buf.buf = []
  buf.start = 0
  buf.len = 0
}

///|
const SEGMENT_SIZE = 1024

///|
/// Ensure the buffer can hold at least `n` bytes starting from `start`.
///
/// - If there is enough space after `start`, nothing changes.
/// - If the capacity is enough but space after `start` is not, the buffer is
///   compacted so valid bytes start at offset 0.
/// - If the capacity is insufficient, a new buffer is allocated with size
///   rounded up to a 1024-byte segment.
///
/// # Example
/// ```mbt check
/// test "enlarge compacts in-place" {
///   let buf = Buffer::new(5)
///   buf.buf[3] = b'x'
///   buf.buf[4] = b'y'
///   buf.start = 3
///   buf.len = 2
///   Buffer::enlarge_to(buf, 4)
///   inspect(buf.start, content="0")
///   inspect(buf.buf.length(), content="5")
///   inspect(buf.len, content="2")
///   let view = buf.buf.unsafe_reinterpret_as_bytes()[:buf.len]
///   inspect(view, content="b\"xy\"")
/// }
/// ```
///
/// ```mbt check
/// test "enlarge grows to segment size" {
///   let buf = Buffer::new(4)
///   buf.buf[1] = b'a'
///   buf.buf[2] = b'b'
///   buf.start = 1
///   buf.len = 2
///   Buffer::enlarge_to(buf, 7)
///   inspect(buf.start, content="0")
///   inspect(buf.buf.length(), content="1024")
///   let view = buf.buf.unsafe_reinterpret_as_bytes()[:buf.len]
///   inspect(view, content="b\"ab\"")
/// }
/// ```
pub fn Buffer::enlarge_to(self : Buffer, n : Int) -> Unit {
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
/// Drop `n` bytes from the front of the buffer.
///
/// If all bytes are dropped, `start` is reset to 0.
///
/// # Example
/// ```mbt check
/// test "drop advances window" {
///   let buf = Buffer::new(6)
///   buf.start = 1
///   buf.len = 4
///   Buffer::drop(buf, 2)
///   inspect(buf.start, content="3")
///   inspect(buf.len, content="2")
/// }
/// ```
///
/// ```mbt check
/// test "drop to empty resets start" {
///   let buf = Buffer::new(3)
///   buf.start = 2
///   buf.len = 1
///   Buffer::drop(buf, 1)
///   inspect(buf.start, content="0")
///   inspect(buf.len, content="0")
/// }
/// ```
pub fn Buffer::drop(self : Buffer, n : Int) -> Unit {
  guard n <= self.len
  self.len -= n
  if self.len == 0 {
    self.start = 0
  } else {
    self.start += n
  }
}
