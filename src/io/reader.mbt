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
/// The `Reader` trait provides asynchronous reading capabilities from various data sources.
/// 
/// This trait supports three levels of granularity:
/// - `read()` for incremental, best-effort reads into existing buffers
/// - `read_exactly()` for reading precise amounts of data
/// - `read_all()` for draining entire streams into memory
///
/// ## Usage
///
/// Most implementations will only need to provide `read()`. The other methods
/// have default implementations that build upon `read()`.
pub(open) trait Reader {
  /// Read data from the source into a buffer.
  ///
  /// This method performs a best-effort read, meaning it may read less than
  /// the requested amount. A return value of 0 indicates that the reader
  /// has reached EOF (end of file).
  ///
  /// # Parameters
  /// - `buffer`: The buffer to read data into
  /// - `offset`: Starting position in the buffer (default: 0)
  /// - `max_len`: Maximum number of bytes to read (default: buffer length - offset)
  ///
  /// # Returns
  /// The number of bytes actually read. Returns 0 when EOF is reached.
  async read(Self, FixedArray[Byte], offset? : Int, max_len? : Int) -> Int
  
  /// Read exactly the specified number of bytes.
  ///
  /// This method will keep reading until either `len` bytes are read
  /// or the reader reaches EOF. If EOF is reached before `len` bytes
  /// are read, `ReaderClosed` is raised.
  ///
  /// # Parameters
  /// - `len`: The exact number of bytes to read
  ///
  /// # Returns
  /// A `Bytes` object containing exactly `len` bytes
  ///
  /// # Errors
  /// Raises `ReaderClosed` if EOF is reached before reading `len` bytes.
  async read_exactly(Self, len : Int) -> Bytes = _
  
  /// Read all remaining data from the source.
  ///
  /// This method drains the entire reader into memory and returns
  /// a `&Data` handle that provides convenient conversion methods.
  ///
  /// # Returns
  /// A `&Data` object containing all remaining data from the reader
  async read_all(Self) -> &Data = _
}

///|
/// Error raised when attempting to read from a closed or EOF reader.
/// 
/// This error is typically raised by `read_exactly()` when the reader
/// reaches EOF before the requested number of bytes can be read.
pub suberror ReaderClosed derive(Show)

///|
/// Default implementation of `read_exactly` that loops until the requested
/// number of bytes are read or the reader reaches EOF.
impl Reader with read_exactly(self, len) {
  let buf = FixedArray::make(len, b'0')
  for received = 0; received < len; {
    let new_received = self.read(buf, offset=received, max_len=len - received)
    if new_received == 0 {
      raise ReaderClosed
    }
    continue received + new_received
  }
  buf.unsafe_reinterpret_as_bytes()
}

///|
/// Default implementation of `read_all` that reads the entire stream
/// into memory using a growing buffer strategy.
impl Reader with read_all(self) {
  let buffer_list = []
  let mut buffer = FixedArray::make(1024, b'0')
  let mut offset = 0
  while self.read(buffer, offset~, max_len=buffer.length() - offset) is n &&
        n > 0 {
    offset += n
    if offset == buffer.length() {
      buffer_list.push(buffer)
      buffer = FixedArray::make(1024, b'0')
      offset = 0
    }
  }
  let total_size = buffer_list.length() * 1024 + offset
  let result = FixedArray::make(total_size, b'0')
  for i, buf in buffer_list {
    result.unsafe_blit(i * 1024, buf, 0, 1024)
  }
  result.unsafe_blit(buffer_list.length() * 1024, buffer, 0, offset)
  result.unsafe_reinterpret_as_bytes()
}
