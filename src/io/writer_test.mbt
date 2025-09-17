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
test "write large data" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      let data = Bytes::make(1024 * 16, 0)
      w.write(data)
    })
    root.spawn_bg(fn() { log.write_object(r.read_all().length()) })
  })
  inspect(log.to_string(), content="16384")
}

///|
test "write reader" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r1, w1) = @pipe.pipe()
    let (r2, w2) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer r2.close()
      defer w1.close()
      w1.write_reader(r2)
    })
    root.spawn_bg(fn() {
      defer r1.close()
      let buf = FixedArray::make(1024, b'0')
      while r1.read(buf) is n && n > 0 {
        @async.sleep(10)
        log.write_string("received \{buf.unsafe_reinterpret_as_bytes()[:n]}\n")
      }
    })
    root.spawn_bg(fn() {
      defer w2.close()
      w2.write(b"abcd")
      log.write_string("sending 4 bytes\n")
      @async.sleep(20)
      w2.write(b"efgh")
      log.write_string("sending 4 bytes\n")
      @async.sleep(20)
      w2.write(b"ijkl")
      log.write_string("sending 4 bytes\n")
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|sending 4 bytes
      #|received b"\x61\x62\x63\x64"
      #|sending 4 bytes
      #|received b"\x65\x66\x67\x68"
      #|sending 4 bytes
      #|received b"\x69\x6a\x6b\x6c"
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
impl @io.Writer for DummyWriter with write_once(self, buf, offset~, len~) {
  guard offset < len
  @async.sleep(self.base_timeout)
  self.logger.write_string("writing byte \{buf[offset]}\n")
  1
}

///|
test "write cancel" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(_) {
    let writer = { logger: log, base_timeout: 40 }
    @async.with_timeout(60, fn() { writer.write(b"abcd") })
  })
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
test "write_string" {
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    defer r.close()
    root.spawn_bg(fn() {
      defer w.close()
      w.write_string("abcd中文☺", encoding=UTF8)
    })
    inspect(@encoding/utf8.decode(r.read_all()), content="abcd中文☺")
  })
}
