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
test "merge multiple" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    root.add_defer(() => r.close())
    root.add_defer(() => w.close())
    root.spawn_bg(fn() {
      @process.run("sh", ["-c", "echo abcd"], stdout=w, extra_env={
        b"LANG": b"en_US.UTF-8",
      })
      |> ignore
    })
    root.spawn_bg(fn() {
      @process.run("sh", ["-c", "sleep 1; echo efgh"], stdout=w, extra_env={
        b"LANG": b"en_US.UTF-8",
      })
      |> ignore
    })
    root.spawn_bg(no_wait=true, fn() {
      let buf = FixedArray::make(1024, b'0')
      while r.read(buf) is n && n > 0 {
        let data = buf.unsafe_reinterpret_as_bytes()[0:n]
        log.write_string(@bytes_util.ascii_to_string(data))
      }
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|abcd
      #|efgh
      #|
    ),
  )
}

///|
test "redirect to file" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let input_file = b"src/process/redirect_test_in.txt"
    let output_file = b"src/process/redirect_test_out.txt"
    root.add_defer(() => @fs.remove(input_file))
    root.add_defer(() => @fs.remove(output_file))
    @fs.write_file(input_file, "abcd", create=0o644)
    let _ = @process.run(
      "cat",
      [],
      stdin=@process.redirect_from_file(input_file),
      stdout=@process.redirect_to_file(output_file, create=0o644),
    )
    log.write_string(@fs.read_file(output_file) |> @bytes_util.ascii_to_string)
  })
  inspect(log.to_string(), content="abcd")
}

///|
test "merge stdout and stderr" {
  @async.with_event_loop(fn(root) {
    let (r, w) = @process.read_from_process()
    defer r.close()
    root.spawn_bg(fn() {
      @process.run("sh", ["-c", "echo abcd; echo efgh >&2"], stdout=w, stderr=w)
      |> ignore
    })
    inspect(
      @bytes_util.ascii_to_string(r.read_all()),
      content=(
        #|abcd
        #|efgh
        #|
      ),
    )
  })
}
