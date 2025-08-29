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
  mut len : Int
}

///|
const SEGMENT_SIZE = 1024

///|
/// Create a new buffered reader that wrap around an existing reader.
pub fn[R] BufferedReader::new(reader : R) -> BufferedReader[R] {
  { reader, buf: FixedArray::make(SEGMENT_SIZE, 0), len: 0 }
}

///|
fn[R] BufferedReader::enlarge_to(self : Self[R], n : Int) -> Unit {
  if n <= self.buf.length() {
    return
  }
  let padding = n % SEGMENT_SIZE
  let target_len = if padding == 0 { n } else { n - padding + SEGMENT_SIZE }
  let new_buf = FixedArray::make(target_len, b'0')
  self.buf.blit_to(new_buf, src_offset=0, dst_offset=0, len=self.buf.length())
  self.buf = new_buf
}

///|
async fn[R : Reader] BufferedReader::ensure(
  self : Self[R],
  len : Int,
) -> Unit raise {
  if self.len >= len {
    return
  }
  self.enlarge_to(len)
  while self.len < len {
    let n = self.reader.read(self.buf, offset=self.len, max_len=len - self.len)
    if n == 0 {
      raise ReaderClosed
    }
    self.len += n
  }
}

///|
async fn[R : Reader] BufferedReader::fetch_more(self : Self[R]) -> Unit raise {
  self.enlarge_to(self.len + SEGMENT_SIZE)
  let n = self.reader.read(
    self.buf,
    offset=self.len,
    max_len=self.buf.length() - self.len,
  )
  if n == 0 {
    raise ReaderClosed
  }
  self.len += n
}

///|
/// `reader.drop(n)` drops the first `n` bytes of data in the reader.
/// If there are no enough data to drop,
/// `BufferedReader` will request more data from the inner reader.
/// If the inner reader is closed before enough data is available,
/// `ReaderClosed` will be rasied.
///
/// This operation will advance the reader stream,
/// and will affect the semantic of all index based operations.
pub async fn[R : Reader] BufferedReader::drop(
  self : Self[R],
  n : Int,
) -> Unit raise {
  self.ensure(n)
  if n < self.len {
    self.buf.blit_to(self.buf, src_offset=n, len=self.len - n)
  }
  self.len -= n
}

///|
pub impl[R : Reader] Reader for BufferedReader[R] with read(
  self,
  buf,
  offset~,
  max_len~,
) {
  if self.len > 0 {
    let n = @cmp.minimum(max_len, self.len)
    self.buf.blit_to(buf, dst_offset=offset, len=n)
    self.drop(n)
    n
  } else {
    self.reader.read(buf, offset~, max_len~)
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
pub async fn[R : Reader] BufferedReader::read(
  self : Self[R],
  buf : FixedArray[Byte],
  offset? : Int = 0,
  max_len? : Int = buf.length() - offset,
) -> Int raise {
  Reader::read(self, buf, offset~, max_len~)
}

///|
/// Get the nth byte from the start of the reader.
/// If there are no enough data available,
/// `BufferedReader` will request more data from the inner reader.
/// If the inner reader is closed before enough data is available,
/// `ReaderClosed` will be rasied.
/// `op_get` will not advance the reader stream,
/// so this operation is idempotent.
pub async fn[R : Reader] BufferedReader::op_get(
  self : Self[R],
  index : Int,
) -> Byte raise {
  self.ensure(index + 1)
  self.buf[index]
}

///|
/// Get a slice of data from the reader,
/// `start` and `end` count from start of stream.
/// If there are no enough data available,
/// `BufferedReader` will request more data from the inner reader.
/// If the inner reader is closed before enough data is available,
/// `ReaderClosed` will be rasied.
/// `op_as_view` will not advance the reader stream,
/// so this operation is idempotent.
pub async fn[R : Reader] BufferedReader::op_as_view(
  self : Self[R],
  start? : Int = 0,
  end~ : Int,
) -> Bytes raise {
  guard start < end
  self.ensure(end)
  self.buf.unsafe_reinterpret_as_bytes()[start:end].to_bytes()
}

///|
/// Find the start index of the first occurence of `bytes` in the reader.
/// The returned index is counted from start of reader.
/// If the target substring is not found in buffered data,
/// `BufferedReader` will request more data from the inner reader.
/// If the inner reader is closed before the target substring is found,
/// `ReaderClosed` will be rasied.
/// `find` will not advance the reader stream,
/// so this operation is idempotent.
pub async fn[R : Reader] BufferedReader::find(
  self : Self[R],
  target : Bytes,
) -> Int raise {
  for searched = 0 {
    let region = self.buf.unsafe_reinterpret_as_bytes()[searched:self.len]
    if region.find(target) is Some(i) {
      return searched + i
    }
    let searched = self.len
    self.fetch_more()
    continue searched
  }
}
