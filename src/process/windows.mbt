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
#cfg(platform="windows")
priv struct OsEnv(@c_buffer.Buffer)

///|
#cfg(platform="windows")
extern "C" fn get_curr_env() -> OsEnv = "moonbitlang_async_get_curr_env"

///|
#cfg(platform="windows")
extern "C" fn OsEnv::length(self : OsEnv) -> Int = "moonbitlang_async_env_block_length"

///|
#cfg(platform="windows")
extern "C" fn OsEnv::new(size : Int) -> OsEnv = "moonbitlang_async_allocate_env_block"

///|
#cfg(platform="windows")
extern "C" fn OsEnv::write_env_block(dst : OsEnv, block : OsEnv) -> Unit = "moonbitlang_async_write_env_block"

///|
#cfg(platform="windows")
#borrow(key, value)
extern "C" fn OsEnv::add_entry(
  dst : OsEnv,
  index : Int,
  key~ : String,
  key_len~ : Int,
  value~ : String,
  value_len~ : Int,
) -> Unit = "moonbitlang_async_env_block_add_entry"

///|
#cfg(any(target="wasm", platform="windows"))
fn StringBuilder::write_arg_with_windows_escape(
  builder : StringBuilder,
  arg : StringView,
) -> Unit {
  if arg is "" {
    builder.write("\"\"")
    return
  }
  // Do not add double quotes if it is unnecessary to do so.
  // This help with simple cases when the program is not using C argv syntax,
  // such as `rundll32.exe`.
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
    }
    segment_start = index + skip
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
#cfg(any(target="wasm", platform="windows"))
async fn raw_spawn_windows(
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
  let command_line = @os_string.encode(command_line.to_string())
  let cwd = match cwd {
    None => None
    Some(cwd) => Some(@os_string.encode(cwd))
  }
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
  let extra_env_len = for k, v in extra_env; acc = 0 {
    continue acc + k.length() + v.length() + 2
  } nobreak {
    acc
  }
  let (env, extra_env_offset) = if inherit_env {
    let curr_env = get_curr_env()
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
  @event_loop.spawn_windows(
    command_line,
    env=env.0,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    no_console_window~,
    is_orphan~,
    context~,
  )
}

///|
#cfg(platform="windows")
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
  raw_spawn_windows(
    cmd,
    args,
    extra_env~,
    inherit_env~,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    no_console_window~,
    is_orphan~,
    context~,
  )
}
