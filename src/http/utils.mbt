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
fn parse_int(src : @bytes.View, base~ : Int) -> Int? {
  for i = 0, acc = 0; i < src.length(); {
    match src[i] {
      '0'..='9' as c => {
        let digit = (c - '0').to_int()
        guard digit < base else { return None }
        continue i + 1, acc * base + digit
      }
      'a'..='z' as c => {
        let digit = (c - 'a').to_int() + 10
        guard digit < base else { return None }
        continue i + 1, acc * base + digit
      }
      'A'..='Z' as c => {
        let digit = (c - 'A').to_int() + 10
        guard digit < base else { return None }
        continue i + 1, acc * base + digit
      }
      _ => return None
    }
  } else {
    Some(acc)
  }
}

///|
fn encode_int(value : Int, base~ : Int) -> Bytes {
  let len = for x = value, len = 1; x >= base; {
    continue x / base, len + 1
  } else {
    len
  }
  let out = FixedArray::make(len, b'0')
  for x = value, i = len - 1; i >= 0; x = x / base, i = i - 1 {
    let digit = x % base
    let chr = if digit < 10 { digit + '0' } else { digit - 10 + 'a' }
    out[i] = chr.to_byte()
  }
  out.unsafe_reinterpret_as_bytes()
}

///|
fn @bytes.View::find_index(self : @bytes.View, byte : Byte) -> Int? {
  for i in 0..<self.length() {
    if self[i] == byte {
      break Some(i)
    }
  } else {
    None
  }
}

///|
fn @bytes.View::to_lower_case(ident : @bytes.View) -> Bytes {
  let result = FixedArray::make(ident.length(), b'0')
  for i in 0..<ident.length() {
    match ident[i] {
      'A'..='Z' as b => result[i] = b - 'A' + 'a'
      b => result[i] = b
    }
  }
  result.unsafe_reinterpret_as_bytes()
}
