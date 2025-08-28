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
test "set cwd" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    guard @env.current_dir() is Some(prev_cwd)
    let (r, w) = @pipe.pipe()
    defer r.close()
    root.spawn_bg(fn() {
      let _ = @process.run(b"ls", [], stdout=w, cwd="src/process", extra_env={
        b"LANG": b"en_US.UTF-8",
      })
      guard @env.current_dir() is Some(new_cwd)
      guard prev_cwd == new_cwd
    })
    let buf = FixedArray::make(1024, b'0')
    while r.read(buf) is n && n > 0 {
      let data = buf.unsafe_reinterpret_as_bytes()[0:n]
      log.write_string(@bytes_util.ascii_to_string(data))
    }
  })
  inspect(
    log.to_string(),
    content=(
      #|basic_test.mbt
      #|cancel_test.mbt
      #|cwd_test.mbt
      #|env_test.mbt
      #|moon.pkg.json
      #|pkg.generated.mbti
      #|process.mbt
      #|stub.c
      #|wait_test.mbt
      #|
    ),
  )
}
