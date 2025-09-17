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
async fn writer(log : StringBuilder, w : @pipe.PipeWrite) -> Unit {
  defer w.close()
  @async.sleep(20)
  log.write_string("writing 4 bytes of data\n")
  w.write(b"abcd")
  @async.sleep(20)
  log.write_string("writing 4 bytes of data\n")
  w.write(b"efgh")
  @async.sleep(20)
  log.write_string("writing 4 bytes of data\n")
  w.write(b"ijkl")
}

///|
async test "BufferedReader::read" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(() => writer(log, w))
    defer r.close()
    let reader = @io.BufferedReader::new(r)
    let buf = FixedArray::make(6, b'0')
    while reader.read(buf) is n && n > 0 {
      log.write_string("received: \{buf.unsafe_reinterpret_as_bytes()[0:n]}\n")
    }
    log.write_string("buffered reader closed\n")
  })
  inspect(
    log.to_string(),
    content=(
      #|writing 4 bytes of data
      #|received: b"\x61\x62\x63\x64"
      #|writing 4 bytes of data
      #|received: b"\x65\x66\x67\x68"
      #|writing 4 bytes of data
      #|received: b"\x69\x6a\x6b\x6c"
      #|buffered reader closed
      #|
    ),
  )
}

///|
async test "BufferedReader::read_exactly" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(() => writer(log, w))
    defer r.close()
    let reader = @io.BufferedReader::new(r)
    for {
      let data = reader.read_exactly(6)
      log.write_string("received: \{data}\n")
    }
  }) catch {
    err => log.write_object(err)
  }
  inspect(
    log.to_string(),
    content=(
      #|writing 4 bytes of data
      #|writing 4 bytes of data
      #|received: b"\x61\x62\x63\x64\x65\x66"
      #|writing 4 bytes of data
      #|received: b"\x67\x68\x69\x6a\x6b\x6c"
      #|ReaderClosed
    ),
  )
}

///|
async test "BufferedReader::op_get" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_task_group(fn(root) {
      let (r, w) = @pipe.pipe()
      root.spawn_bg(() => writer(log, w))
      defer r.close()
      let reader = @io.BufferedReader::new(r)
      log.write_string("reader[5]: \{reader[5]}\n")
      // should be idempotent
      log.write_string("reader[5]: \{reader[5]}\n")
      log.write_string("reader.drop(4)\n")
      reader.drop(4)
      log.write_string("reader[5]: \{reader[5]}\n")
      log.write_string("reader.drop(4)\n")
      reader.drop(4)
      log.write_string("reader[5]: \{reader[5]}\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|writing 4 bytes of data
      #|writing 4 bytes of data
      #|reader[5]: b'\x66'
      #|reader[5]: b'\x66'
      #|reader.drop(4)
      #|writing 4 bytes of data
      #|reader[5]: b'\x6A'
      #|reader.drop(4)
      #|Err(ReaderClosed)
    ),
  )
}

///|
async test "BufferedReader::op_as_view" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_task_group(fn(root) {
      let (r, w) = @pipe.pipe()
      root.spawn_bg(() => writer(log, w))
      defer r.close()
      let reader = @io.BufferedReader::new(r)
      log.write_string("reader[0:6]: \{reader[0:6]}\n")
      // should be idempotent
      log.write_string("reader[0:6]: \{reader[0:6]}\n")
      log.write_string("reader.drop(4)\n")
      reader.drop(4)
      log.write_string("reader[0:6]: \{reader[0:6]}\n")
      log.write_string("reader.drop(4)\n")
      reader.drop(4)
      log.write_string("reader[0:6]: \{reader[0:6]}\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|writing 4 bytes of data
      #|writing 4 bytes of data
      #|reader[0:6]: b"\x61\x62\x63\x64\x65\x66"
      #|reader[0:6]: b"\x61\x62\x63\x64\x65\x66"
      #|reader.drop(4)
      #|writing 4 bytes of data
      #|reader[0:6]: b"\x65\x66\x67\x68\x69\x6a"
      #|reader.drop(4)
      #|Err(ReaderClosed)
    ),
  )
}

///|
async test "BufferedReader::find single byte" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_task_group(fn(root) {
      let (r, w) = @pipe.pipe()
      root.spawn_bg(fn() {
        defer w.close()
        @async.sleep(20)
        log.write_string("writing 4 bytes of data\n")
        w.write(b"abcd")
        @async.sleep(20)
        log.write_string("writing 4 bytes of data\n")
        w.write(b"efgh")
        @async.sleep(20)
        log.write_string("writing 4 bytes of data\n")
        w.write(b"abcd")
      })
      defer r.close()
      let reader = @io.BufferedReader::new(r)
      let i = reader.find(b"a")
      log.write_string("index of 'a': \{i}\n")
      // should be idempotent
      let i = reader.find(b"a")
      log.write_string("index of 'a': \{i}\n")
      log.write_string("reader.drop(4)\n")
      reader.drop(4)
      let i = reader.find(b"a")
      log.write_string("index of 'a': \{i}\n")
      log.write_string("reader.drop(4)\n")
      reader.drop(4)
      let i = reader.find(b"a")
      log.write_string("index of 'a': \{i}\n")
      let i = reader.find(b"x")
      log.write_string("index of 'x': \{i}\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|writing 4 bytes of data
      #|index of 'a': 0
      #|index of 'a': 0
      #|reader.drop(4)
      #|writing 4 bytes of data
      #|writing 4 bytes of data
      #|index of 'a': 4
      #|reader.drop(4)
      #|index of 'a': 0
      #|Err(ReaderClosed)
    ),
  )
}

///|
async test "BufferedReader::find bytes" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_task_group(fn(root) {
      let (r, w) = @pipe.pipe()
      root.spawn_bg(fn() {
        defer w.close()
        @async.sleep(20)
        log.write_string("writing 4 bytes of data\n")
        w.write(b"abcd")
        @async.sleep(20)
        log.write_string("writing 4 bytes of data\n")
        w.write(b"aBcd")
        @async.sleep(20)
        log.write_string("writing 4 bytes of data\n")
        w.write(b"abcd")
      })
      defer r.close()
      let reader = @io.BufferedReader::new(r)
      let i = reader.find(b"ab")
      log.write_string("index of \"ab\": \{i}\n")
      let i = reader.find(b"aB")
      log.write_string("index of \"aB\": \{i}\n")
      log.write_string("reader.drop(4)\n")
      reader.drop(4)
      let i = reader.find(b"ab")
      log.write_string("index of \"ab\": \{i}\n")
      log.write_string("reader.drop(4)\n")
      reader.drop(4)
      let i = reader.find(b"ab")
      log.write_string("index of \"ab\": \{i}\n")
      let i = reader.find(b"aB")
      log.write_string("index of \"aB\": \{i}\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|writing 4 bytes of data
      #|index of "ab": 0
      #|writing 4 bytes of data
      #|index of "aB": 4
      #|reader.drop(4)
      #|writing 4 bytes of data
      #|index of "ab": 4
      #|reader.drop(4)
      #|index of "ab": 0
      #|Err(ReaderClosed)
    ),
  )
}

///|
async test "lazy drop" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(fn() {
      w.write("abcd")
      @async.sleep(20)
      w.write("efgh")
    })
    defer r.close()
    let reader = @io.BufferedReader::new(r)
    let _ = reader.read_exactly(2)
    log.write_string(reader[:2] |> @bytes_util.ascii_to_string)
    let _ = reader.read_exactly(4)
    log.write_string(reader[:2] |> @bytes_util.ascii_to_string)
  })
  inspect(log.to_string(), content="cdgh")
}
