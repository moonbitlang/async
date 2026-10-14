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
/// Run a process and collect its standard output.
/// Return the exit code of the process and the content of its standard output.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_stdout_binary(
  cmd : StringView,
  args : ArrayView[String],
  extra_env~ : Map[String, String] = Map([]),
  inherit_env~ : Bool = true,
  stdin? : &ProcessInput,
  stderr? : &ProcessOutput,
  cwd? : StringView,
  no_console_window? : Bool,
) -> (Int32, Bytes) {
  let mut result = None
  @async.with_task_group() <| group => {
    let child = spawn(
      group,
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout=read_from_process(),
      stderr?,
      cwd?,
      no_console_window?,
    )
    defer child.stdout.close()
    // The caller cannot obtain these channels
    child.stdin.close()
    child.stderr.close()
    let output = child.stdout.read_all()
    result = Some((child.wait(), output))
  }
  result.unwrap()
}

///|
/// Run a process and collect its standard output as UTF-8 encoded text.
/// Return the exit code of the process and the content of its standard output.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_stdout_text(
  cmd : StringView,
  args : ArrayView[String],
  extra_env~ : Map[String, String] = Map([]),
  inherit_env~ : Bool = true,
  stdin? : &ProcessInput,
  stderr? : &ProcessOutput,
  cwd? : StringView,
  no_console_window? : Bool,
) -> (Int32, String) {
  let mut result = None
  @async.with_task_group() <| group => {
    let child = spawn(
      group,
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout=read_from_process(),
      stderr?,
      cwd?,
      no_console_window?,
    )
    defer child.stdout.close()
    // The caller cannot obtain these channels
    child.stdin.close()
    child.stderr.close()
    let output = child.stdout.text.read_all()
    result = Some((child.wait(), output))
  }
  result.unwrap()
}

///|
/// Run a process and collect its standard error.
/// Return the exit code of the process and the content of its standard error.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_stderr_binary(
  cmd : StringView,
  args : ArrayView[String],
  extra_env~ : Map[String, String] = Map([]),
  inherit_env~ : Bool = true,
  stdin? : &ProcessInput,
  stdout? : &ProcessOutput,
  cwd? : StringView,
  no_console_window? : Bool,
) -> (Int32, Bytes) {
  let mut result = None
  @async.with_task_group() <| group => {
    let child = spawn(
      group,
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout?,
      stderr=read_from_process(),
      cwd?,
      no_console_window?,
    )
    defer child.stderr.close()
    // The caller cannot obtain these channels
    child.stdin.close()
    child.stdout.close()
    let output = child.stderr.read_all()
    result = Some((child.wait(), output))
  }
  result.unwrap()
}

///|
/// Run a process and collect its standard error as UTF-8 encoded text.
/// Return the exit code of the process and the content of its standard error.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_stderr_text(
  cmd : StringView,
  args : ArrayView[String],
  extra_env~ : Map[String, String] = Map([]),
  inherit_env~ : Bool = true,
  stdin? : &ProcessInput,
  stdout? : &ProcessOutput,
  cwd? : StringView,
  no_console_window? : Bool,
) -> (Int32, String) {
  let mut result = None
  @async.with_task_group() <| group => {
    let child = spawn(
      group,
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout?,
      stderr=read_from_process(),
      cwd?,
      no_console_window?,
    )
    defer child.stderr.close()
    // The caller cannot obtain these channels
    child.stdin.close()
    child.stdout.close()
    let output = child.stderr.text.read_all()
    result = Some((child.wait(), output))
  }
  result.unwrap()
}

///|
/// Run a process and collect its standard output & standard error.
/// Return the exit code of the process, the content of its standard output,
/// and the content of its standard error.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_output_binary(
  cmd : StringView,
  args : ArrayView[String],
  extra_env~ : Map[String, String] = Map([]),
  inherit_env~ : Bool = true,
  stdin? : &ProcessInput,
  cwd? : StringView,
  no_console_window? : Bool,
) -> (Int32, Bytes, Bytes) {
  let mut result = None
  @async.with_task_group() <| group => {
    let child = spawn(
      group,
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout=read_from_process(),
      stderr=read_from_process(),
      cwd?,
      no_console_window?,
    )
    // The caller cannot obtain this channel
    child.stdin.close()
    let stdout = group.spawn(() => {
      defer child.stdout.close()
      child.stdout.read_all()
    })
    let stderr = group.spawn(() => {
      defer child.stderr.close()
      child.stderr.read_all()
    })
    result = Some((child.wait(), stdout.wait(), stderr.wait()))
  }
  result.unwrap()
}

///|
/// Run a process and collect its standard output & standard error as UTF-8 encoded text.
/// Return the exit code of the process, the content of its standard output,
/// and the content of its standard error.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_output_text(
  cmd : StringView,
  args : ArrayView[String],
  extra_env~ : Map[String, String] = Map([]),
  inherit_env~ : Bool = true,
  stdin? : &ProcessInput,
  cwd? : StringView,
  no_console_window? : Bool,
) -> (Int32, String, String) {
  let mut result = None
  @async.with_task_group() <| group => {
    let child = spawn(
      group,
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout=read_from_process(),
      stderr=read_from_process(),
      cwd?,
      no_console_window?,
    )
    // The caller cannot obtain this channel
    child.stdin.close()
    let stdout = group.spawn(() => {
      defer child.stdout.close()
      child.stdout.text.read_all()
    })
    let stderr = group.spawn(() => {
      defer child.stderr.close()
      child.stderr.text.read_all()
    })
    result = Some((child.wait(), stdout.wait(), stderr.wait()))
  }
  result.unwrap()
}

///|
/// Run a process, merge and collect its standard output & standard error.
/// Return the exit code of the process,
/// and the content of its standard output and standard error.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_output_merged_binary(
  cmd : StringView,
  args : Array[String],
  extra_env~ : Map[String, String] = Map([]),
  inherit_env~ : Bool = true,
  stdin? : &ProcessInput,
  cwd? : StringView,
  no_console_window? : Bool,
) -> (Int32, Bytes) {
  let mut result = None
  @async.with_task_group() <| group => {
    let child = spawn(
      group,
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout=read_from_process(),
      stderr=duplicate_stdout(),
      cwd?,
      no_console_window?,
    )
    defer child.stdout.close()
    // The caller cannot obtain this channel
    child.stdin.close()
    let output = child.stdout.read_all()
    result = Some((child.wait(), output))
  }
  result.unwrap()
}

///|
/// Run a process, merge and collect its standard output & standard error as UTF-8 encoded text.
/// Return the exit code of the process,
/// and the content of its standard output and standard error.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_output_merged_text(
  cmd : StringView,
  args : Array[String],
  extra_env~ : Map[String, String] = Map([]),
  inherit_env~ : Bool = true,
  stdin? : &ProcessInput,
  cwd? : StringView,
  no_console_window? : Bool,
) -> (Int32, String) {
  let mut result = None
  @async.with_task_group() <| group => {
    let child = spawn(
      group,
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout=read_from_process(),
      stderr=duplicate_stdout(),
      cwd?,
      no_console_window?,
    )
    defer child.stdout.close()
    // The caller cannot obtain this channel
    child.stdin.close()
    let output = child.stdout.text.read_all()
    result = Some((child.wait(), output))
  }
  result.unwrap()
}
