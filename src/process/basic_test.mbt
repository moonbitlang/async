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
async test "basic_ls" {
  @async.with_task_group(fn(root) {
    let (r, w) = @process.read_from_process()
    defer r.close()
    root.spawn_bg(fn() {
      @process.run("ls", ["src/process"], stdout=w, extra_env={
        "LANG": "en_US.UTF-8",
      })
      |> ignore
    })
    inspect(
      r.read_all().text(),
      content=(
        #|basic_test.mbt
        #|cancel_test.mbt
        #|cwd_test.mbt
        #|env_test.mbt
        #|helper_test.mbt
        #|moon.pkg.json
        #|pkg.generated.mbti
        #|process.mbt
        #|README.mbt.md
        #|README.md
        #|redirect_test.mbt
        #|stub.c
        #|wait_test.mbt
        #|

      ),
    )
  })
}

///|
async test "basic_cat" {
  @async.with_task_group(fn(root) {
    let (cat_read, we_write) = @process.write_to_process()
    let (we_read, cat_write) = @process.read_from_process()
    root.spawn_bg(fn() {
      @process.run("cat", ["-"], stdin=cat_read, stdout=cat_write) |> ignore
    })
    root.spawn_bg(fn() {
      defer we_write.close()
      we_write.write(b"abcd\n")
      @async.sleep(50)
      we_write.write(b"defg\n")
    })
    root.spawn_bg(fn() {
      defer we_read.close()
      inspect(
        we_read.read_all().text(),
        content=(
          #|abcd
          #|defg
          #|
        ),
      )
    })
  })
}
