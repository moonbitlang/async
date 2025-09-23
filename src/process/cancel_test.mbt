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
async test "cancel process" {
  let test_prog =
    #|sleep 10 &
    #|child=$!
    #|trap "echo received SIGTERM; kill -s TERM $child" TERM
    #|wait $child
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = @process.read_from_process()
    let task = root.spawn(allow_failure=true, fn() {
      defer log.write_string("process terminates\n")
      @process.run("sh", ["-c", test_prog], stdout=w)
    })
    root.spawn_bg(fn() {
      defer r.close()
      let buf = FixedArray::make(1024, b'0')
      while r.read(buf) is n && n > 0 {
        let data = buf.unsafe_reinterpret_as_bytes()[0:n]
          |> @bytes_util.ascii_to_string
        log.write_string("from process: \{data}")
      }
    })
    @async.sleep(200)
    task.cancel()
    log.write_string("cancelling task running process\n")
  })
  inspect(
    log.to_string(),
    content=(
      #|cancelling task running process
      #|process terminates
      #|from process: received SIGTERM
      #|
    ),
  )
}

///|
async test "orphan process" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = @process.read_from_process()
    let task = root.spawn(allow_failure=true, fn() {
      defer log.write_string("process terminates\n")
      @process.run(
        "sh",
        ["-c", "echo first; sleep 1; echo second"],
        stdout=w,
        orphan=true,
      )
    })
    root.spawn_bg(fn() {
      defer r.close()
      let buf = FixedArray::make(1024, b'0')
      while r.read(buf) is n && n > 0 {
        let data = buf.unsafe_reinterpret_as_bytes()[0:n]
          |> @bytes_util.ascii_to_string
        log.write_string("from process: \{data}")
      }
    })
    @async.sleep(500)
    task.cancel()
    log.write_string("cancelling task running process\n")
  })
  inspect(
    log.to_string(),
    content=(
      #|from process: first
      #|cancelling task running process
      #|process terminates
      #|from process: second
      #|
    ),
  )
}
