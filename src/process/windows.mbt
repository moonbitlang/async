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
#borrow(out)
extern "C" fn curr_env_fill(out : String, len : Int) -> Int = "moonbitlang_async_curr_env_fill"

///|
#cfg(platform="windows")
fn get_curr_env() -> String {
  let buffer_len = 32768
  let buffer = String::make(buffer_len, '\u{0}')
  let actual_len = curr_env_fill(buffer, buffer_len)
  if 0 < actual_len && actual_len <= buffer_len {
    buffer[:actual_len].to_owned()
  } else if actual_len > buffer_len {
    let result = String::make(actual_len, '\u{0}')
    if curr_env_fill(result, actual_len) == actual_len {
      result
    } else {
      ""
    }
  } else {
    ""
  }
}

///|
#cfg(platform="windows")
let curr_env : String = get_curr_env()

///|
#cfg(platform="windows")
fn StringBuilder::write_arg_with_windows_escape(
  builder : StringBuilder,
  arg : StringView,
) -> Unit {
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
  is_orphan~ : Bool,
  context~ : String,
) -> @event_loop.Process {
  let cmd = match cmd {
    [.., .. ".exe"] => cmd
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
  let env = match (inherit_env, extra_env.is_empty()) {
    (true, true) => None
    (false, true) => Some(@os_string.encode("\u{0}"))
    (_, false) => {
      let env = StringBuilder::new()
      for key, value in extra_env {
        env
        ..write_string(key)
        ..write_char('=')
        ..write_string(value)
        .write_string("\u{0}")
      }
      if inherit_env {
        env.write_string(curr_env)
      } else {
        env <+ "\u{0}"
      }
      Some(@os_string.encode(env.to_string()))
    }
  }
  @event_loop.spawn(
    command_line,
    env~,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    is_orphan~,
    context~,
  )
}
