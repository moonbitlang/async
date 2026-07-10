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
fn shell(command : String) -> (String, Array[String]) {
  if @event_loop.platform is Windows {
    ("powershell.exe", ["-NoProfile", "-Command", command])
  } else {
    ("/bin/sh", ["-c", command])
  }
}

///|
fn write_stdout_command(text : String) -> String {
  if @event_loop.platform is Windows {
    "[Console]::Out.Write('\{text}')"
  } else {
    "printf '\{text}'"
  }
}

///|
fn write_env_command(name : String) -> String {
  if @event_loop.platform is Windows {
    "[Console]::Out.Write($env:\{name})"
  } else {
    "printf \"$\{name}\""
  }
}

///|
fn list_directory_command() -> String {
  if @event_loop.platform is Windows {
    "Get-ChildItem -Name"
  } else {
    "ls"
  }
}

///|
async test "wasm collect stdout" {
  let (cmd, args) = shell(write_stdout_command("moonbit-process"))
  let (code, output) = @process.collect_stdout(cmd, args)
  inspect(code, content="0")
  inspect(output.text(), content="moonbit-process")
}

///|
async test "wasm pass env" {
  let (cmd, args) = shell(write_env_command("MOONBIT_PROCESS_TEST"))
  let (code, output) = @process.collect_stdout(cmd, args, extra_env={
    "MOONBIT_PROCESS_TEST": "env-ok",
  })
  inspect(code, content="0")
  inspect(output.text(), content="env-ok")
}

///|
async test "wasm set cwd" {
  let (cmd, args) = shell(list_directory_command())
  let (code, output) = @process.collect_stdout(
    cmd,
    args,
    cwd="test_directory",
    extra_env={ "LC_ALL": "C" },
  )
  inspect(code, content="0")
  let files = output
    .text()
    .trim(char_set="\n\r ")
    .replace_all(old="\r\n", new="\n")
    .split("\n")
    .to_array()
  files.sort()
  json_inspect(files, content=["file", "inner1"])
}

///|
async test "wasm reject nul argument" {
  try @process.run("bad\u{0}cmd", []) catch {
    _ => inspect(true, content="true")
  } noraise {
    _ => fail("expected process argument validation to fail")
  }
}
