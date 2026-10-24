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
test "console UTF-8 decoder preserves slices and UTF-16 units" {
  let cases : Array[(Bytes, Array[UInt16])] = [
    (b"\xffA\xce\xbb\xf0\x9f\x99\x82\xff", [0x41, 0x03bb, 0xd83d, 0xde42]),
    (b"\xffA\xc0\xaf\xe2\x82B\xff", [0x41, 0xfffd, 0xfffd, 0xfffd, 0x42]),
    (b"\xff\xef\xbb\xbf\xff", [0xfeff]),
    (b"\xff\xff", []),
  ]
  for (src, expected) in cases {
    let dst = FixedArray::make(16, UInt16(0xaaaa))
    let written = utf8_decode_lossy_to_utf16(
      src~,
      src_offset=1,
      src_len=src.length() - 2,
      dst~,
      dst_offset=2,
    )
    assert_eq(written, expected.length())
    for i in 0..<dst.length() {
      assert_eq(
        dst[i],
        if i >= 2 && i < 2 + written {
          expected[i - 2]
        } else {
          0xaaaa
        },
      )
    }
  }
}
