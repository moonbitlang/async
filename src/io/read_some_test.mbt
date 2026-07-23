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
async test "read_some basic" {
  let log = StringBuilder::new()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => writer(log, w))
    while r.read_some() is Some(chunk) {
      log.write_string("received chunk: \{@utf8.decode(chunk)}\n")
    }
  }
  inspect(
    log,
    content=(
      #|writing 4 bytes of data
      #|received chunk: abcd
      #|writing 4 bytes of data
      #|received chunk: efgh
      #|writing 4 bytes of data
      #|received chunk: ijkl
      #|
    ),
  )
}

///|
async test "read_some length limit 1" {
  let log = StringBuilder::new()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => writer(log, w))
    while r.read_some(max_len=2) is Some(chunk) {
      log.write_string("received chunk: \{@utf8.decode(chunk)}\n")
    }
  }
  inspect(
    log,
    content=(
      #|writing 4 bytes of data
      #|received chunk: ab
      #|received chunk: cd
      #|writing 4 bytes of data
      #|received chunk: ef
      #|received chunk: gh
      #|writing 4 bytes of data
      #|received chunk: ij
      #|received chunk: kl
      #|
    ),
  )
}

///|
async test "read_some length limit 2" {
  let log = StringBuilder::new()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => writer(log, w))
    for max_len = 2; ; max_len = max_len * 2 {
      guard r.read_some(max_len~) is Some(chunk) else { break }
      log.write_string("received chunk: \{@utf8.decode(chunk)}\n")
    }
  }
  inspect(
    log,
    content=(
      #|writing 4 bytes of data
      #|received chunk: ab
      #|received chunk: cd
      #|writing 4 bytes of data
      #|received chunk: efgh
      #|writing 4 bytes of data
      #|received chunk: ijkl
      #|
    ),
  )
}

///|
async test "read_some length limit 3" {
  let log = StringBuilder::new()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg() <| () => {
      defer w.close()
      w.write("abcdefghijkl")
    }
    for max_len = 2; ; max_len = max_len * 2 {
      guard r.read_some(max_len~) is Some(chunk) else { break }
      log.write_string("received chunk: \{@utf8.decode(chunk)}\n")
    }
  }
  inspect(
    log,
    content=(
      #|received chunk: ab
      #|received chunk: cdef
      #|received chunk: ghijkl
      #|
    ),
  )
}

///|
async test "read_some returned chunks remain stable" {
  @async.with_task_group() <| root => {
    let first_expected = Bytes::make(1024, b'a')
    let second_expected = Bytes::make(1024, b'b')
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg() <| () => {
      defer w.close()
      w.write(first_expected)
      w.write(second_expected)
    }
    guard r.read_some(max_len=1024) is Some(first) else {
      fail("missing first chunk")
    }
    guard r.read_some(max_len=1024) is Some(second) else {
      fail("missing second chunk")
    }
    assert_eq(first, first_expected)
    assert_eq(second, second_expected)
  }
}
