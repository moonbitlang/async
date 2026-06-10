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
let crc32_table : FixedArray[UInt] = FixedArray::makei(256, i => {
  let mut crc = i.reinterpret_as_uint()
  for _ in 0..<8 {
    crc = if (crc & 1U) == 0U { crc >> 1 } else { (crc >> 1) ^ 0xedb88320U }
  }
  crc
})

///|
fn crc32_update(current : UInt, chunk : BytesView) -> UInt {
  // Pull out the backing Bytes + start offset once and index that
  // directly. `for byte in chunk` desugars through BytesView::iter +
  // Iter::next (15-16% in a gzip_roundtrip profile), and even
  // `chunk[i]` (= BytesView::at) is a non-inlined function call
  // (6.88% before this change). Indexing the raw Bytes is intrinsic.
  let mut crc = current
  let bytes = chunk.data()
  let start = chunk.start_offset()
  let len = chunk.length()
  for i in 0..<len {
    let index = ((crc ^ bytes[start + i].to_uint()) & 0xffU).reinterpret_as_int()
    crc = crc32_table[index] ^ (crc >> 8)
  }
  crc
}
