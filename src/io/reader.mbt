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
pub(open) trait Reader {
  async read(Self, FixedArray[Byte], offset~ : Int, max_len~ : Int) -> Int raise
  async read_exactly(Self, len : Int) -> Bytes raise = _
  async read_all(Self) -> Bytes raise = _
}

///|
pub suberror ReaderClosed derive(Show)

///|
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
