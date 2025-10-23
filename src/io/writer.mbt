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
/// Text encoding formats supported by the writer.
/// 
/// Currently only UTF-8 encoding is supported.
pub(all) enum Encoding {
  /// UTF-8 encoding for text data
  UTF8
}

///|
/// The `Writer` trait provides asynchronous writing capabilities to various destinations.
/// 
/// This trait supports writing different types of data:
/// - Raw bytes via `write_once()` and `write()`
/// - Any `Data` type via `write()`
/// - Streaming data from readers via `write_reader()`
/// - Text strings via `write_string()` (deprecated)
///
/// ## Usage
///
/// Most implementations will only need to provide `write_once()`. The other methods
/// have default implementations that build upon `write_once()`.
pub(open) trait Writer {
  /// Perform a single write operation.
  ///
  /// This method attempts to write data once and returns the number of bytes
  /// actually written. It may write less than the requested amount, requiring
  /// the caller to handle partial writes.
  ///
  /// # Parameters
  /// - `data`: The bytes to write
  /// - `offset`: Starting position in the data (default: 0)
  /// - `len`: Number of bytes to write (default: data length - offset)
  ///
  /// # Returns
  /// The number of bytes actually written
  async write_once(Self, Bytes, offset~ : Int, len~ : Int) -> Int
  
  /// Write data completely to the destination.
  ///
  /// This method ensures all data is written by making multiple calls to
  /// `write_once()` if necessary. It accepts any type that implements `Data`.
  ///
  /// # Parameters
  /// - `data`: The data to write (Bytes, String, Json, etc.)
  async write(Self, &Data) -> Unit = _
  
  /// Stream data from a reader to this writer.
  ///
  /// This method efficiently copies data from a reader to this writer
  /// without loading all data into memory at once. It's ideal for
  /// large data transfers or streaming scenarios.
  ///
  /// # Parameters
  /// - `reader`: The reader to copy data from
  async write_reader(Self, &Reader) -> Unit = _
  
  /// Write a string with specified encoding.
  ///
  /// @deprecated Use `write()` instead, which accepts strings directly.
  ///
  /// # Parameters
  /// - `str`: The string to write
  /// - `encoding`: The text encoding to use (only UTF8 supported)
  #deprecated("use `write` instead")
  async write_string(Self, StringView, encoding~ : Encoding) -> Unit = _
}

///|
/// Default implementation of `write` that handles complete data writing
/// by making multiple calls to `write_once()` as needed.
impl Writer with write(self, data) {
  let view = data.to_bytesview()
  let start = view.start_offset()
  let len = view.length()
  guard len > 0 else { return }
  let end = start + len
  let offset = self.write_once(view.data(), offset=start, len~)
  if offset == end {
    return
  }
  for offset = start + offset; offset < end; {
    let progress = self.write_once(view.data(), offset~, len=end - offset)
    continue offset + progress
  }
}

///|
/// Default implementation of `write_reader` that streams data from
/// a reader to this writer using a fixed-size buffer.
impl Writer with write_reader(self, reader) {
  let buf = FixedArray::make(1024, b'0')
  while reader.read(buf, offset=0, max_len=1024) is n && n > 0 {
    for offset = 0; offset < n; {
      let progress = self.write_once(
        buf.unsafe_reinterpret_as_bytes(),
        offset~,
        len=n - offset,
      )
      continue offset + progress
    }
  }
}

///|
/// Default implementation of `write_string` (deprecated).
/// This method converts the string to UTF-8 bytes and writes them.
impl Writer with write_string(self, str, encoding~) {
  guard encoding is UTF8
  let data = @encoding/utf8.encode(str, bom=false)
  self.write(data)
}
