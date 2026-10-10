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
#cfg(any(target="native", target="wasm"))
let cat : @async.Lazy[String] = Lazy(() => {
  // Note: the `cat` example program lies in another MoonBit module.
  // Currently, dependencies of a module is built locally in that module,
  // so there will be no build lock conflict between this test and the `cat` program.
  let exit_code = @process.run("moon", [
    "build", "--debug", "test_programs/cat", "--target-dir", "_build/test_programs",
  ])
  guard exit_code is 0 else {
    fail("failed to build `cat` program: \{exit_code}")
  }
  "./_build/test_programs/native/debug/build/moonbitlang/async_test_programs/cat/cat.exe"
})

///|
#cfg(any(target="native", target="wasm"))
async test "redirect_file" {
  let cat = cat.wait()
  let out_file = "_build/stdio_file_test"
  let code = @process.run(
    cat,
    [],
    stdin=@process.redirect_from_file("moon.mod"),
    stdout=@process.redirect_to_file(out_file),
  )
  inspect(code, content="0")
  assert_eq(@fs.read_file(out_file).text(), @fs.read_file("moon.mod").text())
}

///|
#cfg(any(target="native", target="wasm"))
async test "redirect pipe" {
  @async.with_task_group() <| group => {
    let cat = cat.wait()
    let child = @process.spawn(
      group,
      cat,
      [],
      stdin=@process.write_to_process(),
      stdout=@process.read_from_process(),
    )
    group.spawn_bg() <| () => {
      defer child.stdin.close()
      child.stdin.write(b"abcd\n")
      @async.sleep(50)
      child.stdin.write(b"defg\n")
    }
    defer child.stdout.close()
    inspect(
      child.stdout.read_all().text(),
      content=(
        #|abcd
        #|defg
        #|
      ),
    )
    inspect(child.wait(), content="0")
  }
}

///|
#cfg(any(target="native", target="wasm"))
async test "stdio cancel" {
  let cat = cat.wait()
  @async.with_task_group() <| group => {
    let child = @process.spawn(
      group,
      cat,
      ["-timeout", "500"],
      stdin=@process.write_to_process(),
      stdout=@process.read_from_process(),
      stderr=@process.read_from_process(),
    )
    defer child.stdin.close()
    defer child.stdout.close()
    defer child.stderr.close()
    child.stdin.write("abcd")
    debug_inspect(
      child.stdout.read_some(),
      content=(
        #|Some(<Bytes: [0x61, 0x62, 0x63, 0x64]>)
      ),
    )
    @async.sleep(750)
    assert_eq(child.stdout.read_all().text(), "")
    inspect(
      child.stderr.read_all().text().trim(chars="\r\n"),
      content="TimeoutError",
    )
    inspect(child.wait(), content="1")
  }
}

///|
#cfg(any(target="native", target="wasm"))
async test "stdout and stderr are the same" {
  let cat = cat.wait()
  @async.with_task_group <| group => {
    let child = @process.spawn(
      group,
      cat,
      [],
      stdin=@process.write_to_process(),
      stdout=@process.read_from_process(),
      stderr=@process.duplicate_stdout(),
    )
    defer child.stdout.close()
    {
      defer child.stdin.close()
      child.stdin.write("abcd")
    }
    inspect(
      child.stdout.read_all().text(),
      content=(
        #|abcd
      ),
    )
  }
}
