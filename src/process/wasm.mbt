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
fn StringBuilder::write_arg_with_windows_escape(
  builder : StringBuilder,
  arg : StringView,
) -> Unit {
  guard @event_loop.platform is Windows else {
    builder.write_stringview(arg)
    return
  }
  let need_quote = for char in arg {
    if char is (' ' | '\t' | '"') {
      break true
    }
  } nobreak {
    false
  }
  if !need_quote {
    builder.write_stringview(arg)
    return
  }
  let mut segment_start = 0
  let mut index = 0
  let mut trailing_backslash = 0
  fn flush(skip : Int) {
    if index > segment_start {
      builder.write_stringview(arg[segment_start:index - trailing_backslash])
      if trailing_backslash > 0 {
        builder.write_string(String::make(trailing_backslash * 2, '\\'))
      }
      segment_start = index + skip
    }
  }

  builder.write_char('"')
  while index < arg.length() {
    match arg.code_unit_at(index) {
      '"' => {
        flush(1)
        builder <+ "\\\""
      }
      '\\' => trailing_backslash += 1
      _ => trailing_backslash = 0
    }
    index += 1
  }
  flush(0)
  builder.write_char('"')
}

///|
priv struct OsArgv(UInt64)

///|
priv struct OsEnv(UInt64)

///|
#unsafe_skip_stub_check
fn get_curr_env() -> OsEnv = "moonbitlang/async" "process/get_curr_env"

///|
#unsafe_skip_stub_check
fn OsEnv::length(self : OsEnv) -> Int = "moonbitlang/async" "process/env_block_length"

///|
#unsafe_skip_stub_check
fn OsEnv::new(size : Int) -> OsEnv = "moonbitlang/async" "process/allocate_env_block"

///|
#unsafe_skip_stub_check
fn OsEnv::free(self : OsEnv) -> Unit = "moonbitlang/async" "process/free_env"

///|
#unsafe_skip_stub_check
fn OsEnv::write_env_block(dst : OsEnv, block : OsEnv) -> Unit = "moonbitlang/async" "process/write_env_block"

///|
#unsafe_skip_stub_check
#borrow(key, value)
fn OsEnv::add_entry(
  dst : OsEnv,
  index_or_offset : Int,
  key~ : String,
  key_len~ : Int,
  value~ : String,
  value_len~ : Int,
) -> Unit = "moonbitlang/async" "process/env_block_add_entry"

///|
#unsafe_skip_stub_check
fn OsArgv::new(size : Int) -> OsArgv = "moonbitlang/async" "process/make_argv_array/unix"

///|
#unsafe_skip_stub_check
fn OsArgv::free(self : OsArgv) -> Unit = "moonbitlang/async" "process/free_argv"

///|
#unsafe_skip_stub_check
#borrow(arg)
fn OsArgv::add_encoded_entry(
  self : OsArgv,
  offset : Int,
  arg : @os_string.OsString,
  arg_len~ : Int,
) -> Unit = "moonbitlang/async" "process/argv_array_add_encoded_entry/unix"

///|
#unsafe_skip_stub_check
#borrow(arg)
fn OsArgv::add_entry(
  self : OsArgv,
  offset : Int,
  arg : String,
  arg_len~ : Int,
) -> Unit = "moonbitlang/async" "process/argv_array_add_entry/unix"

///|
async fn raw_spawn(
  cmd : StringView,
  args : ArrayView[String],
  extra_env~ : Map[String, String],
  inherit_env~ : Bool,
  stdin~ : &ProcessInput?,
  stdout~ : &ProcessOutput?,
  stderr~ : &ProcessOutput?,
  cwd~ : StringView?,
  no_console_window~ : Bool,
  is_orphan~ : Bool,
  context~ : String,
) -> @event_loop.Process {
  check_process_arguments(cmd, args, extra_env, cwd)
  defer {
    if stdin is Some(p) {
      p.after_spawn()
    }
    if stdout is Some(p) {
      p.after_spawn()
    }
    if stderr is Some(p) {
      p.after_spawn()
    }
  }
  let stdin = match stdin {
    Some(pipe) => pipe.fd()
    None => @fd_util.invalid_fd
  }
  let stdout = match stdout {
    Some(pipe) => pipe.fd()
    None => @fd_util.invalid_fd
  }
  let stderr = match stderr {
    Some(pipe) => pipe.fd()
    None => @fd_util.invalid_fd
  }
  let cwd = match cwd {
    None => None
    Some(cwd) => Some(@os_string.encode(cwd))
  }
  if @event_loop.platform is Windows {
    let cmd = match cmd {
      [.., '.', 'e' | 'E', 'x' | 'X', 'e' | 'E']
      | [.., '.', 'c' | 'C', 'o' | 'O', 'm' | 'M'] => cmd
      _ => cmd + ".exe"
    }
    let command_line = StringBuilder::new()
    command_line.write_arg_with_windows_escape(cmd)
    for arg in args {
      command_line..write_char(' ').write_arg_with_windows_escape(arg)
    }
    let extra_env_len = for k, v in extra_env; acc = 0 {
      continue acc + k.length() + v.length() + 2
    } nobreak {
      acc
    }
    let (env, extra_env_offset) = if inherit_env {
      let curr_env = get_curr_env()
      defer curr_env.free()
      let curr_env_len = curr_env.length()
      let env = OsEnv::new(curr_env_len + extra_env_len)
      env.write_env_block(curr_env)
      (env, curr_env_len)
    } else {
      (OsEnv::new(extra_env_len), 0)
    }
    for k, v in extra_env; offset = extra_env_offset {
      let key_len = k.length()
      let value_len = v.length()
      env.add_entry(offset, key=k, key_len~, value=v, value_len~)
      continue offset + key_len + value_len + 2
    }
    defer env.free()
    @event_loop.spawn_windows(
      @os_string.encode(command_line.to_string()),
      env=env.0,
      stdin~,
      stdout~,
      stderr~,
      cwd~,
      no_console_window~,
      is_orphan~,
      context~,
    )
  } else {
    let cmd = @os_string.encode(cmd)
    let argv = OsArgv::new(args.length() + 1)
    defer argv.free()
    argv.add_encoded_entry(0, cmd, arg_len=cmd.to_string().length())
    for i, arg in args {
      argv.add_entry(i + 1, arg, arg_len=arg.length())
    }
    let extra_count = extra_env.length()
    let (env, inherited_env_entry_count) = if inherit_env {
      let curr_env = get_curr_env()
      defer curr_env.free()
      let curr_env_len = curr_env.length()
      let env = OsEnv::new(curr_env_len + extra_count)
      env.write_env_block(curr_env)
      (env, curr_env_len)
    } else {
      (OsEnv::new(extra_count), 0)
    }
    for k, v in extra_env; i = inherited_env_entry_count; i = i + 1 {
      let key_len = k.length()
      let value_len = v.length()
      env.add_entry(i, key=k, key_len~, value=v, value_len~)
    }
    defer env.free()
    @event_loop.spawn_unix(
      cmd,
      argv.0,
      env=env.0,
      inherited_env_entry_count~,
      stdin~,
      stdout~,
      stderr~,
      cwd~,
      context~,
    )
  }
}
