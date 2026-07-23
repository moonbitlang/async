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
