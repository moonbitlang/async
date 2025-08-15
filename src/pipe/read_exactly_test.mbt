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
test "read_exactly" {
  let buf = StringBuilder::new()
  fn log(msg) {
    buf..write_string(msg).write_char('\n')
  }

  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    // reader
    root.spawn_bg(fn() {
      defer r.close()
      let msg1 = r.read_exactly(4)
      @async.sleep(10)
      log("first message: \{msg1}")
      let msg2 = r.read_exactly(4)
      @async.sleep(10)
      log("second message: \{msg2}")
      let msg3 = r.read_exactly(4)
      @async.sleep(10)
      log("third message: \{msg3}")
    })
    // writer
    root.spawn_bg(fn() {
      defer w.close()
      w.write([1, 2, 3, 4, 5, 6])
      log("first message sent")
      @async.sleep(50)
      w.write([7, 8, 9, 10, 11, 12])
      log("second message sent")
    })
  })
  inspect(
    buf.to_string(),
    content=(
      #|first message sent
      #|first message: b"\x01\x02\x03\x04"
      #|second message sent
      #|second message: b"\x05\x06\x07\x08"
      #|third message: b"\x09\x0a\x0b\x0c"
      #|
    ),
  )
}

///|
test "read_exactly failure" {
  let buf = StringBuilder::new()
  fn log(msg) {
    buf..write_string(msg).write_char('\n')
  }

  let result = try? @async.with_event_loop(fn(root) {
      let (r, w) = @pipe.pipe()
      // reader
      root.spawn_bg(fn() {
        defer r.close()
        let msg1 = r.read_exactly(4)
        @async.sleep(10)
        log("first message: \{msg1}")
        let msg2 = r.read_exactly(4)
        @async.sleep(10)
        log("second message: \{msg2}")
        let msg3 = r.read_exactly(4)
        @async.sleep(10)
        log("third message: \{msg3}")
      })
      // writer
      root.spawn_bg(fn() {
        defer w.close()
        w.write([1, 2, 3, 4, 5, 6])
        log("first message sent")
        @async.sleep(20)
      })
    })
  log(result.to_string())
  inspect(
    buf.to_string(),
    content=(
      #|first message sent
      #|first message: b"\x01\x02\x03\x04"
      #|Err(ReaderClosed)
      #|
    ),
  )
}
