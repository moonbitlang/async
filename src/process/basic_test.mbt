///|
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
fn ascii_to_string(ascii : @bytes.View) -> String {
  let builder = StringBuilder::new()
  for byte in ascii {
    builder.write_char(byte.to_int().unsafe_to_char())
  }
  builder.to_string()
}

///|
test "basic_ls" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    defer r.close()
    root.spawn_bg(fn() {
      @process.run(b"ls", [b"src"], stdout=w, extra_env={ b"LANG": b"C" })
      |> ignore
    })
    let buf = FixedArray::make(1024, b'0')
    while r.read(buf) is n && n > 0 {
      let data = buf.unsafe_reinterpret_as_bytes()[0:n]
      log.write_string(ascii_to_string(data))
    }
  })
  inspect(
    log.to_string(),
    content=(
      #|allow_failure_test.mbt
      #|aqueue
      #|async.mbt
      #|async.mbti
      #|cancellation_test.mbt
      #|examples
      #|fs
      #|group_defer_test.mbt
      #|internal
      #|io
      #|missing_close_test.mbt
      #|moon.pkg.json
      #|no_wait_test.mbt
      #|os_error
      #|pause_test.mbt
      #|pipe
      #|process
      #|protect_from_cancel_test.mbt
      #|retry_test.mbt
      #|return_immediately_test.mbt
      #|socket
      #|spawn_loop_test.mbt
      #|spawn_test.mbt
      #|task.mbt
      #|task_group.mbt
      #|timer_test.mbt
      #|wait_test.mbt
      #|with_timeout_test.mbt
      #|worker_test.mbt
      #|
    ),
  )
}

///|
test "basic_cat" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (cat_read, we_write) = @pipe.pipe()
    let (we_read, cat_write) = @pipe.pipe()
    root.spawn_bg(fn() {
      @process.run(b"cat", [b"-"], stdin=cat_read, stdout=cat_write) |> ignore
    })
    root.spawn_bg(fn() {
      defer we_write.close()
      we_write.write(b"abcd\n")
      @async.sleep(50)
      we_write.write(b"defg\n")
    })
    root.spawn_bg(fn() {
      defer we_read.close()
      let buf = FixedArray::make(1024, b'0')
      while we_read.read(buf) is n && n > 0 {
        let data = buf.unsafe_reinterpret_as_bytes()[0:n]
        log.write_string(ascii_to_string(data))
      }
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|abcd
      #|defg
      #|
    ),
  )
}
