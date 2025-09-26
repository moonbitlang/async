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
async test "read_exactly" {
  let buf = StringBuilder::new()
  fn log(msg) {
    buf..write_string(msg).write_char('\n')
  }

  @async.with_task_group(fn(root) {
    let (r, w) = @pipe.pipe()
    // reader
    root.spawn_bg(fn() {
      defer r.close()
      let msg1 = r.read_exactly(4) |> @encoding/utf8.decode
      @async.sleep(10)
      log("first message: \{msg1}")
      let msg2 = r.read_exactly(4) |> @encoding/utf8.decode
      @async.sleep(10)
      log("second message: \{msg2}")
      let msg3 = r.read_exactly(4) |> @encoding/utf8.decode
      @async.sleep(10)
      log("third message: \{msg3}")
    })
    // writer
    root.spawn_bg(fn() {
      defer w.close()
      w.write("abcdef")
      log("first message sent")
      @async.sleep(50)
      w.write("ghijkl")
      log("second message sent")
    })
  })
  inspect(
    buf.to_string(),
    content=(
      #|first message sent
      #|first message: abcd
      #|second message sent
      #|second message: efgh
      #|third message: ijkl
      #|
    ),
  )
}

///|
async test "read_exactly failure" {
  let buf = StringBuilder::new()
  fn log(msg) {
    buf..write_string(msg).write_char('\n')
  }

  @async.with_task_group(fn(root) {
    let (r, w) = @pipe.pipe()
    // reader
    root.spawn_bg(fn() {
      defer r.close()
      let msg1 = r.read_exactly(4) |> @encoding/utf8.decode
      @async.sleep(10)
      log("first message: \{msg1}")
      let msg2 = r.read_exactly(4) |> @encoding/utf8.decode
      @async.sleep(10)
      log("second message: \{msg2}")
      let msg3 = r.read_exactly(4) |> @encoding/utf8.decode
      @async.sleep(10)
      log("third message: \{msg3}")
    })
    // writer
    root.spawn_bg(fn() {
      defer w.close()
      w.write("abcdef")
      log("first message sent")
      @async.sleep(20)
    })
  }) catch {
    err => log(err.to_string())
  }
  inspect(
    buf.to_string(),
    content=(
      #|first message sent
      #|first message: abcd
      #|ReaderClosed
      #|
    ),
  )
}
