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
async test {
  inspect(
    @process.run("moon", ["build", "-C", "examples", "--debug"]),
    content="0",
  )
  let cat = "./examples/target/native/debug/build/cat/cat.exe"
  // test 2: redirect from/to file
  let out_file = "target/stdio_file_test"
  let code = @process.run(
    cat,
    [],
    stdin=@process.redirect_from_file("moon.mod.json"),
    stdout=@process.redirect_to_file(out_file, create=0o644),
  )
  inspect(code, content="0")
  assert_eq(
    @fs.read_file(out_file).text(),
    @fs.read_file("moon.mod.json").text(),
  )
  // test 2: pipe
  @async.with_task_group(fn(root) {
    let (cat_read, we_write) = @process.write_to_process()
    let (we_read, cat_write) = @process.read_from_process()
    root.spawn_bg(fn() {
      let code = @process.run(cat, [], stdin=cat_read, stdout=cat_write)
      inspect(code, content="0")
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
