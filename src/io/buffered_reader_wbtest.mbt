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
async fn writer(log : StringBuilder, w : PipeWrite) -> Unit {
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
    let (r, w) = pipe()
    root.spawn_bg(() => writer(log, w))
    defer r.close()
    let reader = BufferedReader::new(r)
    let buf = FixedArray::make(6, b'0')
    while reader.read(buf) is n && n > 0 {
      let data = buf.unsafe_reinterpret_as_bytes()[0:n]
      let data = @encoding/utf8.decode(data)
      log.write_string("received: \{data}\n")
    }
    log.write_string("buffered reader closed\n")
  })
  inspect(
    log.to_string(),
    content=(
      #|writing 4 bytes of data
      #|received: abcd
      #|writing 4 bytes of data
      #|received: efgh
      #|writing 4 bytes of data
      #|received: ijkl
      #|buffered reader closed
      #|
    ),
  )
}

///|
async test "BufferedReader::read_exactly" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = pipe()
    root.spawn_bg(() => writer(log, w))
    defer r.close()
    let reader = BufferedReader::new(r)
    for {
      let data = reader.read_exactly(6)
      let data = @encoding/utf8.decode(data)
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
      #|received: abcdef
      #|writing 4 bytes of data
      #|received: ghijkl
      #|ReaderClosed
    ),
  )
}

///|
async test "BufferedReader::op_get" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_task_group(fn(root) {
      let (r, w) = pipe()
      root.spawn_bg(() => writer(log, w))
      defer r.close()
      let reader = BufferedReader::new(r)
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
      let (r, w) = pipe()
      root.spawn_bg(() => writer(log, w))
      defer r.close()
      let reader = BufferedReader::new(r)
      let slice = @encoding/utf8.decode(reader[0:6])
      log.write_string("reader[0:6]: \{slice}\n")
      // should be idempotent
      let slice = @encoding/utf8.decode(reader[0:6])
      log.write_string("reader[0:6]: \{slice}\n")
      log.write_string("reader.drop(4)\n")
      reader.drop(4)
      let slice = @encoding/utf8.decode(reader[0:6])
      log.write_string("reader[0:6]: \{slice}\n")
      log.write_string("reader.drop(4)\n")
      reader.drop(4)
      let slice = @encoding/utf8.decode(reader[0:6])
      log.write_string("reader[0:6]: \{slice}\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|writing 4 bytes of data
      #|writing 4 bytes of data
      #|reader[0:6]: abcdef
      #|reader[0:6]: abcdef
      #|reader.drop(4)
      #|writing 4 bytes of data
      #|reader[0:6]: efghij
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
      let (r, w) = pipe()
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
      let reader = BufferedReader::new(r)
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
      let (r, w) = pipe()
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
      let reader = BufferedReader::new(r)
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
async test "BufferedReader::find_bytes splitted" {
  @async.with_task_group(fn(root) {
    let (r, w) = pipe()
    root.spawn_bg(fn() {
      defer w.close()
      w.write(b"abcd")
      @async.sleep(100)
      w.write(b"efgh")
    })
    defer r.close()
    let reader = BufferedReader::new(r)
    inspect(reader.find_opt("cdef"), content="Some(2)")
  })
}

///|
async test "BufferedReader::find_opt" {
  @async.with_task_group(fn(root) {
    let (r, w) = pipe()
    root.spawn_bg(fn() {
      defer w.close()
      @async.sleep(20)
      w.write(b"abcd")
      @async.sleep(20)
      w.write(b"aBcd")
      @async.sleep(20)
      w.write(b"abcd")
    })
    defer r.close()
    let reader = BufferedReader::new(r)
    inspect(reader.find_opt(b"ab"), content="Some(0)")
    reader.drop(4)
    inspect(reader.find_opt(b"ab"), content="Some(4)")
    reader.drop(8)
    inspect(reader.find_opt(b"ab"), content="None")
  })
}

///|
async test "lazy drop" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = pipe()
    root.spawn_bg(fn() {
      defer w.close()
      w.write("abcd")
      @async.sleep(20)
      w.write("efgh")
    })
    defer r.close()
    let reader = BufferedReader::new(r)
    let _ = reader.read_exactly(2)
    log.write_string(reader[:2] |> @bytes_util.ascii_to_string)
    let _ = reader.read_exactly(4)
    log.write_string(reader[:2] |> @bytes_util.ascii_to_string)
  })
  inspect(log.to_string(), content="cdgh")
}

///|
#cfg(target="native")
async test "BufferedReader::read_line" {
  let file = @fs.open("LICENSE", mode=ReadOnly)
  defer file.close()
  let reader = BufferedReader::new(file)
  let lines = []
  while reader.read_line() is Some(line) {
    lines.push(line)
  }
  inspect(lines.length(), content="202")
  assert_eq(lines.join("\n") + "\n", @fs.read_file("LICENSE").text())
}

///|
#cfg(not(target="native"))
fn _ignore_unused_import() -> Unit {
  ignore(@fs.unimplemented)
}
