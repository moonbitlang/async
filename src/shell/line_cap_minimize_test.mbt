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
async test "min process c cat drained stdout writer closes" {
  guard! @env.get_env_var("MOONBIT_ASYNC_C_CAT_PROG") is Some(program)
  try
    @async.with_task_group() <| group => {
      let (child_stdin, stdin_writer) = @process.write_to_process()
      let (stdout_reader, child_stdout) = @process.read_from_process()
      group.spawn_bg(allow_failure=true, () => {
        defer stdin_writer.close()
        stdin_writer.write("a".repeat(1000))
      })
      group.spawn_bg(() => {
        defer stdout_reader.close()
        let mut buffered = 0
        while stdout_reader.read_some(max_len=4096) is Some(chunk) {
          buffered += chunk.length()
          if buffered > 64 {
            raise BareLineLimitExceeded(64)
          }
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
    BareLineLimitExceeded(64) => ()
    err => raise err
  } noraise {
    _ => fail("expected the line limit to raise")
  }
}

///|
async test "min process c cat pending stdout writer closes" {
  guard! @env.get_env_var("MOONBIT_ASYNC_C_CAT_PROG") is Some(program)
  try
    @async.with_task_group() <| group => {
      let (child_stdin, stdin_writer) = @process.write_to_process()
      let (stdout_reader, child_stdout) = @process.read_from_process()
      group.spawn_bg(allow_failure=true, () => {
        defer stdin_writer.close()
        stdin_writer.write("a".repeat(1000))
      })
      group.spawn_bg(() => {
        defer stdout_reader.close()
        let mut buffered = 0
        while stdout_reader.read_some(max_len=65) is Some(chunk) {
          buffered += chunk.length()
          if buffered > 64 {
            raise BareLineLimitExceeded(64)
          }
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
    BareLineLimitExceeded(64) => ()
    err => raise err
  } noraise {
    _ => fail("expected the line limit to raise")
  }
}

///|
async test "min process c cat no data stdout pipe writer closes" {
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
      group.spawn_bg(() => {
        stdin_writer.close()
        raise BareLineLimitExceeded(64)
      })
      child.wait() |> ignore
    }
  catch {
    BareLineLimitExceeded(64) => ()
    err => raise err
  } noraise {
    _ => fail("expected the line limit to raise")
  }
}

///|
async test "min process c cat no data no stdout pipe writer closes" {
  guard! @env.get_env_var("MOONBIT_ASYNC_C_CAT_PROG") is Some(program)
  try
    @async.with_task_group() <| group => {
      let (child_stdin, stdin_writer) = @process.write_to_process()
      let child = @process.spawn(
        group,
        program,
        [],
        stdin=child_stdin,
        cancel_handler=@process.hard_cancel(),
      )
      group.spawn_bg(() => {
        stdin_writer.close()
        raise BareLineLimitExceeded(64)
      })
      child.wait() |> ignore
    }
  catch {
    BareLineLimitExceeded(64) => ()
    err => raise err
  } noraise {
    _ => fail("expected the line limit to raise")
  }
}

///|
async test "min process c cat no data stdin already eof stdout pipe" {
  guard! @env.get_env_var("MOONBIT_ASYNC_C_CAT_PROG") is Some(program)
  try
    @async.with_task_group() <| group => {
      let (child_stdin, stdin_writer) = @process.write_to_process()
      stdin_writer.close()
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
      group.spawn_bg(() => raise BareLineLimitExceeded(64))
      child.wait() |> ignore
    }
  catch {
    BareLineLimitExceeded(64) => ()
    err => raise err
  } noraise {
    _ => fail("expected synthetic cancellation")
  }
}

///|
async test "min process true no pipes synthetic cancellation" {
  try
    @async.with_task_group() <| group => {
      let child = @process.spawn(
        group,
        "/bin/true",
        [],
        cancel_handler=@process.hard_cancel(),
      )
      group.spawn_bg(() => raise BareLineLimitExceeded(64))
      child.wait() |> ignore
    }
  catch {
    BareLineLimitExceeded(64) => ()
    err => raise err
  } noraise {
    _ => fail("expected synthetic cancellation")
  }
}
