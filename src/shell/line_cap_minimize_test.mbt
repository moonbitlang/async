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
suberror BareLineLimitExceeded {
  BareLineLimitExceeded(Int)
}

///|
async test "min process c cat" {
  guard! @env.get_env_var("MOONBIT_ASYNC_C_CAT_PROG") is Some(program)
  try
    @async.with_task_group() <| group => {
      let (child_stdin, stdin_writer) = @process.write_to_process()
      let (stdout_reader, child_stdout) = @process.read_from_process()
      group.spawn_bg(allow_failure=true, () => {
        defer stdin_writer.close()
        stdin_writer.write(b"a")
      })
      group.spawn_bg(() => {
        defer stdout_reader.close()
        if stdout_reader.read_some(max_len=1) is Some(_) {
          raise BareLineLimitExceeded(0)
        }
      })
      let child = @process.spawn(
        group,
        program,
        [],
        stdin=child_stdin,
        stdout=child_stdout,
        cancel_handler=@process.hard_cancel(),
      )
      child.wait() |> ignore
    }
  catch {
    BareLineLimitExceeded(0) => ()
    err => raise err
  } noraise {
    _ => fail("expected the line limit to raise")
  }
}

///|
async test "min process c cat sequential" {
  guard! @env.get_env_var("MOONBIT_ASYNC_C_CAT_PROG") is Some(program)
  try
    @async.with_task_group() <| group => {
      let (child_stdin, stdin_writer) = @process.write_to_process()
      let (stdout_reader, child_stdout) = @process.read_from_process()
      defer stdout_reader.close()
      let child = @process.spawn(
        group,
        program,
        [],
        stdin=child_stdin,
        stdout=child_stdout,
        cancel_handler=@process.hard_cancel(),
      )
      {
        defer stdin_writer.close()
        stdin_writer.write(b"a")
      }
      if stdout_reader.read_some(max_len=1) is Some(_) {
        raise BareLineLimitExceeded(0)
      }
      child.wait() |> ignore
    }
  catch {
    BareLineLimitExceeded(0) => ()
    err => raise err
  } noraise {
    _ => fail("expected the line limit to raise")
  }
}

///|
async test "min process c cat sequential no read" {
  guard! @env.get_env_var("MOONBIT_ASYNC_C_CAT_PROG") is Some(program)
  try
    @async.with_task_group() <| group => {
      let (child_stdin, stdin_writer) = @process.write_to_process()
      let (stdout_reader, child_stdout) = @process.read_from_process()
      defer stdout_reader.close()
      let _child = @process.spawn(
        group,
        program,
        [],
        stdin=child_stdin,
        stdout=child_stdout,
        cancel_handler=@process.hard_cancel(),
      )
      {
        defer stdin_writer.close()
        stdin_writer.write(b"a")
      }
      (
        {
          raise BareLineLimitExceeded(0)
        } : Unit)
    }
  catch {
    BareLineLimitExceeded(0) => ()
    err => raise err
  } noraise {
    _ => fail("expected the line limit to raise")
  }
}
