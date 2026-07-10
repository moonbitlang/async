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
async test "write large data" {
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      let data = Bytes::make(1024 * 16, 0)
      w.write(data)
    }
    root.spawn_bg() <| () => {
      defer r.close()
      inspect(r.read_all().length(), content="16384")
    }
  }
}

///|
async test "write reader" {
  let log = StringBuilder::new()
  @async.with_task_group() <| root => {
    let (r1, w1) = @io.pipe()
    let (r2, w2) = @io.pipe()
    root.spawn_bg() <| () => {
      defer r2.close()
      defer w1.close()
      w1.write_reader(r2)
    }
    root.spawn_bg() <| () => {
      defer r1.close()
      while r1.read_some() is Some(data) {
        let data = @utf8.decode(data)
        log.write_string("received \{data}\n")
      }
    }
    root.spawn_bg() <| () => {
      defer w2.close()
      log <+ "sending 4 bytes\n"
      w2.write(b"abcd")
      @async.sleep(300)
      log <+ "sending 4 bytes\n"
      w2.write(b"efgh")
      @async.sleep(300)
      log <+ "sending 4 bytes\n"
      w2.write(b"ijkl")
    }
  }
  inspect(
    log.to_string(),
    content=(
      #|sending 4 bytes
      #|received abcd
      #|sending 4 bytes
      #|received efgh
      #|sending 4 bytes
      #|received ijkl
      #|
    ),
  )
}

///|
struct DummyWriter {
  logger : &Logger
  base_timeout : Int
}

///|
impl @io.Writer for DummyWriter with fn write_once(self, buf, offset~, len~) {
  guard offset + len <= buf.length()
  @async.sleep(self.base_timeout)
  let logger = self.logger
  logger <+ "writing byte \{buf[offset]}\n"
  1
}

///|
async test "write cancel" {
  let log = StringBuilder::new()
  let writer = { logger: log, base_timeout: 300 }
  @async.with_timeout_opt(450, () => writer.write(b"abcd")) |> ignore
  // The `write` here is partial and corrupted,
  // but we have no choice because making `write` atomic may cause hang
  inspect(
    log.to_string(),
    content=(
      #|writing byte b'\x61'
      #|
    ),
  )
}

///|
async test "write_text" {
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg() <| () => {
      defer w.close()
      w.write_text("abcd中文☺")
    }
    inspect(r.read_all_text(), content="abcd中文☺")
  }
}

///|
struct ShortWriter {
  logger : &Logger
}

///|
impl @io.Writer for ShortWriter with fn write_once(self, buf, offset~, len~) {
  let written = @cmp.minimum(len, 2)
  self.logger <+
    "\{offset}:\{len}:\{@utf8.decode(buf[offset:offset + written])}\n"
  written
}

///|
async test "write a non-zero-offset byte view through short writes" {
  let log = StringBuilder::new()
  let writer : ShortWriter = { logger: log }
  let data = b"__payload__"
  writer.write(data[2:2])
  writer.write(data[2:9])
  writer.write(data[9:9])
  inspect(
    log.to_string(),
    content=(
      #|2:7:pa
      #|4:5:yl
      #|6:3:oa
      #|8:1:d
      #|
    ),
  )
}

///|
async test "write and read JSON explicitly" {
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg() <| () => {
      defer w.close()
      w.write_json({ "answer": 42, "ok": true })
    }
    json_inspect(r.read_all_json(), content={ "answer": 42, "ok": true })
  }
}
