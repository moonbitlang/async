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
async test "set_env" {
  @async.with_task_group(fn(root) {
    let (r, w) = @process.read_from_process()
    defer r.close()
    root.spawn_bg(fn() {
      let env_var = if is_windows { "$env:MAGIC_VAR" } else { "$MAGIC_VAR" }
      @process.run(shell, ["-c", "\{write_stdout} \{env_var}"], stdout=w, extra_env={
        "MAGIC_VAR": "MAGIC_VALUE",
      })
      |> ignore
    })
    inspect(r.read_all().text(), content="MAGIC_VALUE")
  })
}

///|
async test "set_env no inherit" {
  let test_prog = dump_env_prog.wait()
  @async.with_task_group(fn(root) {
    let (r, w) = @process.read_from_process()
    defer r.close()
    root.spawn_bg(fn() {
      @process.run(
        test_prog,
        [],
        stdout=w,
        extra_env={
          "MAGIC_VAR_1": "MAGIC_VALUE_1",
          "MAGIC_VAR_2": "MAGIC_VALUE_2",
          "MAGIC_VAR_3": "MAGIC_VALUE_3",
          "MAGIC_VAR_4": "MAGIC_VALUE_4",
        },
        inherit_env=false,
      )
      |> ignore
    })
    inspect(
      r.read_all().text().replace_all(old="\r\n", new="\n"),
      content=(
        #|MAGIC_VAR_1=MAGIC_VALUE_1
        #|MAGIC_VAR_2=MAGIC_VALUE_2
        #|MAGIC_VAR_3=MAGIC_VALUE_3
        #|MAGIC_VAR_4=MAGIC_VALUE_4
        #|
      ),
    )
  })
}
