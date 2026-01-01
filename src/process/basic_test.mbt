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
  @async.with_task_group(root => {
    let (r, w) = @process.read_from_process()
    defer r.close()
    root.spawn_bg(fn() {
      @process.run(shell, ["-c", "\{ls} src/process"], stdout=w, extra_env={
        "LC_ALL": "C",
      })
      |> ignore
    })
    let files = r
      .read_all()
      .text()
      .trim(char_set="\n\r ")
      .replace_all(old="\r\n", new="\n")
      .split("\n")
      .to_array()
      |> then(x => {
        x.sort()
        x
      })
    // files.sort()
    @json.inspect(files, content=[
      "stub.c", "unix.mbt", "README.md", "windows.c", "process.mbt", "windows.mbt",
      "cwd_test.mbt", "env_test.mbt", "redirect.mbt", "README.mbt.md", "moon.pkg.json",
      "test_programs", "wait_test.mbt", "basic_test.mbt", "cancel_test.mbt", "helper_test.mbt",
      "cancellation.mbt", "redirect_test.mbt", "unimplemented.mbt", "pkg.generated.mbti",
      "commands_for_test.mbt", "unimplemented_test.mbt", "windows_escape_wbtest.mbt",
    ])
  })
}

///|
async test "basic_cat" {
  let cat = cat.wait()
  @async.with_task_group(fn(root) {
    let (cat_read, we_write) = @process.write_to_process()
    let (we_read, cat_write) = @process.read_from_process()
    root.spawn_bg(fn() {
      @process.run(cat, [], stdin=cat_read, stdout=cat_write) |> ignore
    })
    root.spawn_bg(fn() {
      defer we_write.close()
      we_write.write(b"abcd")
      @async.sleep(50)
      we_write.write(b"efgh")
    })
    root.spawn_bg(fn() {
      defer we_read.close()
      inspect(we_read.read_all().text(), content="abcdefgh")
    })
  })
}
