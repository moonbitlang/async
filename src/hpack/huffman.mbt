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
/// HPACK Huffman encoding table per RFC 7541 Appendix B.
/// 257 entries: symbols 0-255 plus EOS (256).
/// Each entry is (code, bit_length).
let huffman_table : Array[(Int, Int)] = [
  // 0-3
  (0x1ff8, 13),
  (0x7fffd8, 23),
  (0xfffffe2, 28),
  (0xfffffe3, 28),
  // 4-7
  (0xfffffe4, 28),
  (0xfffffe5, 28),
  (0xfffffe6, 28),
  (0xfffffe7, 28),
  // 8-11
  (0xfffffe8, 28),
  (0xffffea, 24),
  (0x3ffffffc, 30),
  (0xfffffe9, 28),
  // 12-15
  (0xfffffea, 28),
  (0x3ffffffd, 30),
  (0xfffffeb, 28),
  (0xfffffec, 28),
  // 16-19
  (0xfffffed, 28),
  (0xfffffee, 28),
  (0xfffffef, 28),
  (0xffffff0, 28),
  // 20-23
  (0xffffff1, 28),
  (0xffffff2, 28),
  (0x3ffffffe, 30),
  (0xffffff3, 28),
  // 24-27
  (0xffffff4, 28),
  (0xffffff5, 28),
  (0xffffff6, 28),
  (0xffffff7, 28),
  // 28-31
  (0xffffff8, 28),
  (0xffffff9, 28),
  (0xffffffa, 28),
  (0xffffffb, 28),
  // 32 ' ' - 35 '#'
  (0x14, 6),
  (0x3f8, 10),
  (0x3f9, 10),
  (0xffa, 12),
  // 36 '$' - 39 '\''
  (0x1ff9, 13),
  (0x15, 6),
  (0xf8, 8),
  (0x7fa, 11),
  // 40 '(' - 43 '+'
  (0x3fa, 10),
  (0x3fb, 10),
  (0xf9, 8),
  (0x7fb, 11),
  // 44 ',' - 47 '/'
  (0xfa, 8),
  (0x16, 6),
  (0x17, 6),
  (0x18, 6),
  // 48 '0' - 51 '3'
  (0x0, 5),
  (0x1, 5),
  (0x2, 5),
  (0x19, 6),
  // 52 '4' - 55 '7'
  (0x1a, 6),
  (0x1b, 6),
  (0x1c, 6),
  (0x1d, 6),
  // 56 '8' - 59 ';'
  (0x1e, 6),
  (0x1f, 6),
  (0x5c, 7),
  (0xfb, 8),
  // 60 '<' - 63 '?'
  (0x7ffc, 15),
  (0x20, 6),
  (0xffb, 12),
  (0x3fc, 10),
  // 64 '@' - 67 'C'
  (0x1ffa, 13),
  (0x21, 6),
  (0x5d, 7),
  (0x5e, 7),
  // 68 'D' - 71 'G'
  (0x5f, 7),
  (0x60, 7),
  (0x61, 7),
  (0x62, 7),
  // 72 'H' - 75 'K'
  (0x63, 7),
  (0x64, 7),
  (0x65, 7),
  (0x66, 7),
  // 76 'L' - 79 'O'
  (0x67, 7),
  (0x68, 7),
  (0x69, 7),
  (0x6a, 7),
  // 80 'P' - 83 'S'
  (0x6b, 7),
  (0x6c, 7),
  (0x6d, 7),
  (0x6e, 7),
  // 84 'T' - 87 'W'
  (0x6f, 7),
  (0x70, 7),
  (0x71, 7),
  (0x72, 7),
  // 88 'X' - 91 '['
  (0xfc, 8),
  (0x73, 7),
  (0xfd, 8),
  (0x1ffb, 13),
  // 92 '\\' - 95 '_'
  (0x7fff0, 19),
  (0x1ffc, 13),
  (0x3ffc, 14),
  (0x22, 6),
  // 96 '`' - 99 'c'
  (0x7ffd, 15),
  (0x3, 5),
  (0x23, 6),
  (0x4, 5),
  // 100 'd' - 103 'g'
  (0x24, 6),
  (0x5, 5),
  (0x25, 6),
  (0x26, 6),
  // 104 'h' - 107 'k'
  (0x27, 6),
  (0x6, 5),
  (0x74, 7),
  (0x75, 7),
  // 108 'l' - 111 'o'
  (0x28, 6),
  (0x29, 6),
  (0x2a, 6),
  (0x7, 5),
  // 112 'p' - 115 's'
  (0x2b, 6),
  (0x76, 7),
  (0x2c, 6),
  (0x8, 5),
  // 116 't' - 119 'w'
  (0x9, 5),
  (0x2d, 6),
  (0x77, 7),
  (0x78, 7),
  // 120 'x' - 123 '{'
  (0x79, 7),
  (0x7a, 7),
  (0x7b, 7),
  (0x7ffe, 15),
  // 124 '|' - 127
  (0x7fc, 11),
  (0x3ffd, 14),
  (0x1ffd, 13),
  (0xffffffc, 28),
  // 128-131
  (0xfffe6, 20),
  (0x3fffd2, 22),
  (0xfffe7, 20),
  (0xfffe8, 20),
  // 132-135
  (0x3fffd3, 22),
  (0x3fffd4, 22),
  (0x3fffd5, 22),
  (0x7fffd9, 23),
  // 136-139
  (0x3fffd6, 22),
  (0x7fffda, 23),
  (0x7fffdb, 23),
  (0x7fffdc, 23),
  // 140-143
  (0x7fffdd, 23),
  (0x7fffde, 23),
  (0xffffeb, 24),
  (0x7fffdf, 23),
  // 144-147
  (0xffffec, 24),
  (0xffffed, 24),
  (0x3fffd7, 22),
  (0x7fffe0, 23),
  // 148-151
  (0xffffee, 24),
  (0x7fffe1, 23),
  (0x7fffe2, 23),
  (0x7fffe3, 23),
  // 152-155
  (0x7fffe4, 23),
  (0x1fffdc, 21),
  (0x3fffd8, 22),
  (0x7fffe5, 23),
  // 156-159
  (0x3fffd9, 22),
  (0x7fffe6, 23),
  (0x7fffe7, 23),
  (0xffffef, 24),
  // 160-163
  (0x3fffda, 22),
  (0x1fffdd, 21),
  (0xfffe9, 20),
  (0x3fffdb, 22),
  // 164-167
  (0x3fffdc, 22),
  (0x7fffe8, 23),
  (0x7fffe9, 23),
  (0x1fffde, 21),
  // 168-171
  (0x7fffea, 23),
  (0x3fffdd, 22),
  (0x3fffde, 22),
  (0xfffff0, 24),
  // 172-175
  (0x1fffdf, 21),
  (0x3fffdf, 22),
  (0x7fffeb, 23),
  (0x7fffec, 23),
  // 176-179
  (0x1fffe0, 21),
  (0x1fffe1, 21),
  (0x3fffe0, 22),
  (0x1fffe2, 21),
  // 180-183
  (0x7fffed, 23),
  (0x3fffe1, 22),
  (0x7fffee, 23),
  (0x7fffef, 23),
  // 184-187
  (0xfffea, 20),
  (0x3fffe2, 22),
  (0x3fffe3, 22),
  (0x3fffe4, 22),
  // 188-191
  (0x7ffff0, 23),
  (0x3fffe5, 22),
  (0x3fffe6, 22),
  (0x7ffff1, 23),
  // 192-195
  (0x3ffffe0, 26),
  (0x3ffffe1, 26),
  (0xfffeb, 20),
  (0x7fff1, 19),
  // 196-199
  (0x3fffe7, 22),
  (0x7ffff2, 23),
  (0x3fffe8, 22),
  (0x1ffffec, 25),
  // 200-203
  (0x3ffffe2, 26),
  (0x3ffffe3, 26),
  (0x3ffffe4, 26),
  (0x7ffffde, 27),
  // 204-207
  (0x7ffffdf, 27),
  (0x3ffffe5, 26),
  (0xfffff1, 24),
  (0x1ffffed, 25),
  // 208-211
  (0x7fff2, 19),
  (0x1fffe3, 21),
  (0x3ffffe6, 26),
  (0x7ffffe0, 27),
  // 212-215
  (0x7ffffe1, 27),
  (0x3ffffe7, 26),
  (0x7ffffe2, 27),
  (0xfffff2, 24),
  // 216-219
  (0x1fffe4, 21),
  (0x1fffe5, 21),
  (0x3ffffe8, 26),
  (0x3ffffe9, 26),
  // 220-223
  (0xffffffd, 28),
  (0x7ffffe3, 27),
  (0x7ffffe4, 27),
  (0x7ffffe5, 27),
  // 224-227
  (0xfffec, 20),
  (0xfffff3, 24),
  (0xfffed, 20),
  (0x1fffe6, 21),
  // 228-231
  (0x3fffe9, 22),
  (0x1fffe7, 21),
  (0x1fffe8, 21),
  (0x7ffff3, 23),
  // 232-235
  (0x3fffea, 22),
  (0x3fffeb, 22),
  (0x1ffffee, 25),
  (0x1ffffef, 25),
  // 236-239
  (0xfffff4, 24),
  (0xfffff5, 24),
  (0x3ffffea, 26),
  (0x7ffff4, 23),
  // 240-243
  (0x3ffffeb, 26),
  (0x7ffffe6, 27),
  (0x3ffffec, 26),
  (0x3ffffed, 26),
  // 244-247
  (0x7ffffe7, 27),
  (0x7ffffe8, 27),
  (0x7ffffe9, 27),
  (0x7ffffea, 27),
  // 248-251
  (0x7ffffeb, 27),
  (0xffffffe, 28),
  (0x7ffffec, 27),
  (0x7ffffed, 27),
  // 252-255
  (0x7ffffee, 27),
  (0x7ffffef, 27),
  (0x7fffff0, 27),
  (0x3ffffee, 26),
  // 256 EOS
  (0x3fffffff, 30),
]

///|
/// Huffman decode tree node.
priv enum HuffmanNode {
  Empty
  Leaf(Int)
  Internal(HuffmanNode, HuffmanNode)
}

///|
/// Build the Huffman decode tree from the encoding table.
fn build_huffman_tree() -> HuffmanNode {
  fn insert(
    node : HuffmanNode,
    code : Int,
    bits : Int,
    symbol : Int,
  ) -> HuffmanNode {
    if bits == 0 {
      return Leaf(symbol)
    }
    let bit = (code >> (bits - 1)) & 1
    let (left, right) = match node {
      Empty => (Empty, Empty)
      Internal(left, right) => (left, right)
      Leaf(_) => abort("huffman tree: inserting into leaf node")
    }
    if bit == 0 {
      Internal(insert(left, code, bits - 1, symbol), right)
    } else {
      Internal(left, insert(right, code, bits - 1, symbol))
    }
  }
  let mut root : HuffmanNode = Empty
  for i = 0; i < huffman_table.length(); i = i + 1 {
    let (code, bit_length) = huffman_table[i]
    root = insert(root, code, bit_length, i)
  }
  root
}

///|
/// Lazily built Huffman decode tree.
let huffman_decode_root : HuffmanNode = build_huffman_tree()

///|
/// Encode bytes using HPACK Huffman coding.
/// Writes bits MSB first. Pads the final byte with 1-bits (EOS prefix).
fn huffman_encode(src : Bytes) -> Bytes {
  let buf = @buffer.new()
  let mut current_byte : Int = 0
  let mut bits_left : Int = 8
  for i = 0; i < src.length(); i = i + 1 {
    let sym = src[i].to_int()
    let (code, code_len) = huffman_table[sym]
    let mut remaining = code_len
    while remaining > 0 {
      if remaining >= bits_left {
        current_byte = current_byte |
          ((code >> (remaining - bits_left)) & ((1 << bits_left) - 1))
        remaining = remaining - bits_left
        buf.write_byte(current_byte.to_byte())
        current_byte = 0
        bits_left = 8
      } else {
        current_byte = current_byte |
          ((code & ((1 << remaining) - 1)) << (bits_left - remaining))
        bits_left = bits_left - remaining
        remaining = 0
      }
    }
  }
  if bits_left < 8 {
    current_byte = current_byte | ((1 << bits_left) - 1)
    buf.write_byte(current_byte.to_byte())
  }
  buf.contents()
}

///|
/// Decode HPACK Huffman-encoded bytes back to original.
fn huffman_decode(src : Bytes) -> Bytes raise {
  let buf = @buffer.new()
  let mut node = huffman_decode_root
  let mut bits_remaining = 0
  let mut current_byte = 0
  let mut byte_index = 0
  let mut padding_bits = 0
  while byte_index < src.length() || bits_remaining > 0 {
    if bits_remaining == 0 {
      if byte_index >= src.length() {
        break
      }
      current_byte = src[byte_index].to_int()
      byte_index = byte_index + 1
      bits_remaining = 8
    }
    let bit = (current_byte >> (bits_remaining - 1)) & 1
    bits_remaining = bits_remaining - 1
    node = match node {
      Empty => abort("huffman_decode: unexpected empty node during traversal")
      Leaf(_) => abort("huffman_decode: unexpected leaf during traversal")
      Internal(left, right) => if bit == 0 { left } else { right }
    }
    match node {
      Leaf(sym) => {
        if sym == 256 {
          raise Failure::Failure("huffman_decode: EOS symbol encountered")
        }
        buf.write_byte(sym.to_byte())
        padding_bits = 0
        node = huffman_decode_root
      }
      Internal(_, _) => padding_bits = padding_bits + 1
      Empty => abort("huffman_decode: reached empty node")
    }
  }
  if padding_bits > 7 {
    raise Failure::Failure("huffman_decode: padding exceeds 7 bits")
  }
  buf.contents()
}
