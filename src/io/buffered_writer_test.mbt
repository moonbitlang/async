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
async test "BufferedWriter" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      let w = @io.BufferedWriter::new(w, size=4)
      w.write("ab")
      log.write_string("2 bytes written\n")
      @async.sleep(20)
      w.write("cd")
      log.write_string("2 bytes written\n")
      @async.sleep(20)
      w.write("ef")
      log.write_string("2 bytes written\n")
      w.flush()
    })
    root.spawn_bg(fn() {
      defer r.close()
      let buf = FixedArray::make(4, b'0')
      while r.read(buf) is n && n > 0 {
        let data = buf.unsafe_reinterpret_as_bytes()[:n]
        log.write_string("received: \{@bytes_util.ascii_to_string(data)}\n")
      }
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|2 bytes written
      #|2 bytes written
      #|2 bytes written
      #|received: abcd
      #|received: ef
      #|
    ),
  )
}

///|
async test "BufferedWriter::write_reader" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r1, w1) = @pipe.pipe()
    let (r2, w2) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer r2.close()
      defer w1.close()
      let w1 = @io.BufferedWriter::new(w1, size=6)
      w1.write_reader(r2)
      w1.flush()
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
      #|sending 4 bytes
      #|received b"\x61\x62\x63\x64\x65\x66"
      #|sending 4 bytes
      #|received b"\x67\x68\x69\x6a\x6b\x6c"
      #|
    ),
  )
}
