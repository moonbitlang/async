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
fn OsEnv::make(extra_env : Map[String, String], inherit_env~ : Bool) -> OsEnv {
  if @event_loop.platform is Windows {
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
    env
  } else {
    let extra_count = extra_env.length()
    let (env, inherited_env_entry_count) = if inherit_env {
      let curr_env = get_curr_env()
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
    env
  }
}

///|
#unsafe_skip_stub_check
fn OsArgv::new(size : Int) -> OsArgv = "moonbitlang/async" "process/make_argv_array/unix"

///|
#unsafe_skip_stub_check
#borrow(arg)
fn OsArgv::add_encoded_entry(
  self : OsArgv,
  offset : Int,
  arg : @os_string.OsString,
  arg_len? : Int = arg.to_string().length(),
) -> Unit = "moonbitlang/async" "process/argv_array_add_encoded_entry/unix"

///|
#unsafe_skip_stub_check
#borrow(arg)
fn OsArgv::add_entry(
  self : OsArgv,
  offset : Int,
  arg : String,
  arg_len? : Int = arg.length(),
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
  match @event_loop.platform {
    Windows =>
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
    Linux | MacOS =>
      raw_spawn_unix(
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
}
