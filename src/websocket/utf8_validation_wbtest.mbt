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
test "validate utf8 single byte" {
  debug_inspect(
    try verify_utf8([0x79], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(0)",
  )
}

///|
test "validate utf8 two bytes" {
  debug_inspect(
    try verify_utf8([0xc0], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(1)",
  )
  debug_inspect(
    try verify_utf8([0xc0, 0x80], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(0)",
  )
  debug_inspect(
    try verify_utf8([0xc0, 0x79], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Err(Malformed(<BytesView: [0xc0, 0x79]>))
    ),
  )
}

///|
test "validate utf8 three bytes" {
  debug_inspect(
    try verify_utf8([0xe0], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(2)",
  )
  debug_inspect(
    try verify_utf8([0xe0, 0x80], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(1)",
  )
  debug_inspect(
    try verify_utf8([0xe0, 0x80, 0x80], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(0)",
  )
  debug_inspect(
    try verify_utf8([0xe0, 0x79], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Err(Malformed(<BytesView: [0xc0, 0x79]>))
    ),
  )
  debug_inspect(
    try verify_utf8([0xe0, 0x80, 0x79], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Err(Malformed(<BytesView: [0xc0, 0x79]>))
    ),
  )
}

///|
test "validate utf8 four bytes" {
  debug_inspect(
    try verify_utf8([0xf0], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(3)",
  )
  debug_inspect(
    try verify_utf8([0xf0, 0x80], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(2)",
  )
  debug_inspect(
    try verify_utf8([0xf0, 0x80, 0x80], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(1)",
  )
  debug_inspect(
    try verify_utf8([0xf0, 0x80, 0x80, 0x80], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(0)",
  )
  debug_inspect(
    try verify_utf8([0xf0, 0x79], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Err(Malformed(<BytesView: [0xc0, 0x79]>))
    ),
  )
  debug_inspect(
    try verify_utf8([0xf0, 0x80, 0x79], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Err(Malformed(<BytesView: [0xc0, 0x79]>))
    ),
  )
  debug_inspect(
    try verify_utf8([0xf0, 0x80, 0x80, 0x79], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Err(Malformed(<BytesView: [0xc0, 0x79]>))
    ),
  )
  debug_inspect(
    try verify_utf8([0xf0, 0x80, 0x80, 0x80, 0x79], remaining=0) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(0)",
  )
}

///|
test "validate utf8 in the middle" {
  debug_inspect(
    try verify_utf8([0x79], remaining=1) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Err(Malformed(<BytesView: [0xc0, 0x79]>))
    ),
  )
  debug_inspect(
    try verify_utf8([0xc0], remaining=1) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Err(Malformed(<BytesView: [0xc0, 0xc0]>))
    ),
  )
  debug_inspect(
    try verify_utf8([0xe0], remaining=1) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Err(Malformed(<BytesView: [0xc0, 0xe0]>))
    ),
  )
  debug_inspect(
    try verify_utf8([0xf0], remaining=1) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Err(Malformed(<BytesView: [0xc0, 0xf0]>))
    ),
  )
  debug_inspect(
    try verify_utf8([0x80], remaining=1) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(0)",
  )
  debug_inspect(
    try verify_utf8([0x80], remaining=2) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(1)",
  )
  debug_inspect(
    try verify_utf8([0x80, 0x80], remaining=3) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(1)",
  )
  debug_inspect(
    try verify_utf8([0x80, 0x80, 0x79], remaining=2) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content="Ok(0)",
  )
  debug_inspect(
    try verify_utf8([0x80, 0x80, 0x80], remaining=2) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Err(Malformed(<BytesView: [0x80]>))
    ),
  )
}
