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
#cfg(not(platform="windows"))
priv struct OsEnvArray(@c_buffer.Buffer)

///|
#cfg(not(platform="windows"))
extern "C" fn get_curr_env() -> OsEnvArray = "moonbitlang_async_get_curr_env"

///|
#cfg(not(platform="windows"))
extern "C" fn OsEnvArray::length(self : OsEnvArray) -> Int = "moonbitlang_async_env_block_length"

///|
#cfg(not(platform="windows"))
extern "C" fn OsEnvArray::new(size : Int) -> OsEnvArray = "moonbitlang_async_allocate_env_block"

///|
#cfg(not(platform="windows"))
extern "C" fn OsEnvArray::write_env_block(
  dst : OsEnvArray,
  block : OsEnvArray,
) -> Unit = "moonbitlang_async_write_env_block"

///|
#cfg(not(platform="windows"))
#borrow(key, value)
extern "C" fn OsEnvArray::add_entry(
  dst : OsEnvArray,
  index : Int,
  key~ : String,
  key_len~ : Int,
  value~ : String,
  value_len~ : Int,
) -> Unit = "moonbitlang_async_env_block_add_entry"

///|
#cfg(not(platform="windows"))
priv struct OsArgv(@c_buffer.Buffer)

///|
#cfg(not(platform="windows"))
extern "C" fn OsArgv::new(size : Int) -> OsArgv = "moonbitlang_async_make_argv_array"

///|
#cfg(not(platform="windows"))
#borrow(arg)
extern "C" fn OsArgv::add_encoded_entry(
  self : OsArgv,
  offset : Int,
  arg : @os_string.OsString,
  arg_len~ : Int,
) -> Unit = "moonbitlang_async_argv_array_add_encoded_entry"

///|
#cfg(not(platform="windows"))
#borrow(arg)
extern "C" fn OsArgv::add_entry(
  self : OsArgv,
  offset : Int,
  arg : String,
  arg_len~ : Int,
) -> Unit = "moonbitlang_async_argv_array_add_entry"

///|
#cfg(not(platform="windows"))
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
  let cmd = @os_string.encode(cmd)
  let cwd = match cwd {
    None => None
    Some(cwd) => Some(@os_string.encode(cwd))
  }
  let argv = OsArgv::new(args.length() + 1)
  argv.add_encoded_entry(0, cmd, arg_len=cmd.bytes_length())
  for i, arg in args {
    argv.add_entry(i + 1, arg, arg_len=arg.length())
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
    None => -1
  }
  let stdout = match stdout {
    Some(pipe) => pipe.fd()
    None => -1
  }
  let stderr = match stderr {
    Some(pipe) => pipe.fd()
    None => -1
  }
  let extra_count = extra_env.length()
  let (env, inherited_env_entry_count) = if inherit_env {
    let curr_env = get_curr_env()
    let curr_env_len = curr_env.length()
    let env = OsEnvArray::new(curr_env_len + extra_count)
    env.write_env_block(curr_env)
    (env, curr_env_len)
  } else {
    (OsEnvArray::new(extra_count), 0)
  }
  for k, v in extra_env; i = inherited_env_entry_count; i = i + 1 {
    let key_len = k.length()
    let value_len = v.length()
    env.add_entry(i, key=k, key_len~, value=v, value_len~)
  }
  // currently auto kill child process on hard termination is not supported on Unix,
  // so `is_orphan` makes no difference on actual spawning
  ignore(is_orphan)
  ignore(no_console_window)
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

///|
let _ignored : Unit = ignore(@os_error.check_errno)
