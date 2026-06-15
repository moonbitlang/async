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
pub struct Process {
  pid : Int
  priv result : @async.Task[Int]
}

///|
pub async fn Process::wait(self : Process) -> Int {
  self.result.wait()
}

///|
pub fn Process::try_wait(self : Process) -> Int? raise {
  self.result.try_wait()
}

///|
pub fn Process::cancel(self : Process) -> Unit {
  self.result.cancel()
}

///|
pub async fn run(
  cmd : StringView,
  args : ArrayView[String],
  extra_env? : Map[String, String] = {},
  inherit_env? : Bool = true,
  stdin? : &ProcessInput,
  stdout? : &ProcessOutput,
  stderr? : &ProcessOutput,
  cwd? : StringView,
  cancel_handler? : CancellationHandler = graceful_cancel(timeout=5000),
) -> Int {
  ignore(cancel_handler)
  let process = raw_spawn(
    cmd,
    args,
    extra_env~,
    inherit_env~,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    context="@process.run()",
  )
  @event_loop.wait_process_handle(process, context="@process.run()")
}

///|
pub async fn[X] spawn(
  group : @async.TaskGroup[X],
  cmd : StringView,
  args : ArrayView[String],
  extra_env? : Map[String, String] = {},
  inherit_env? : Bool = true,
  stdin? : &ProcessInput,
  stdout? : &ProcessOutput,
  stderr? : &ProcessOutput,
  cwd? : StringView,
  cancel_handler? : CancellationHandler = graceful_cancel(timeout=5000),
  no_wait? : Bool,
) -> Process {
  ignore(cancel_handler)
  let process = raw_spawn(
    cmd,
    args,
    extra_env~,
    inherit_env~,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    context="@process.spawn()",
  )
  let pid = process
  let result = group.spawn(no_wait?, () => {
    @event_loop.wait_process_handle(process, context="@process.spawn()")
  })
  { pid, result }
}

///|
fn spawn_process_ffi(
  argv : Int,
  argv_len : Int,
  argc : Int,
  stdin : @fd_util.Fd,
  stdout : @fd_util.Fd,
  stderr : @fd_util.Fd,
) -> Int = "moonbit_v0" "process/spawn_process"

///|
fn spawn_process(
  argv : FixedArray[Byte],
  argv_len : Int,
  argc : Int,
  stdin : @fd_util.Fd,
  stdout : @fd_util.Fd,
  stderr : @fd_util.Fd,
) -> Int {
  let argv_ptr = @wasm_ffi.byte_array_to_owned_ptr(argv)
  defer @wasm_ffi.free(argv_ptr)
  spawn_process_ffi(argv_ptr, argv_len, argc, stdin, stdout, stderr)
}

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
  context~ : String,
) -> Int {
  guard extra_env.is_empty() &&
    inherit_env &&
    stdin is None &&
    stderr is None &&
    cwd is None
  let argv_bytes : Array[Bytes] = []
  argv_bytes.push(@utf8.encode(cmd.to_owned()))
  let mut argv_len = 4 + argv_bytes[0].length()
  for i in 0..<args.length() {
    let bytes = @utf8.encode(args[i])
    argv_len += 4 + bytes.length()
    argv_bytes.push(bytes)
  }
  let argv = FixedArray::make(argv_len, b'\x00')
  let mut offset = 0
  for i in 0..<argv_bytes.length() {
    let bytes = argv_bytes[i]
    write_i32_le(argv, offset, bytes.length())
    offset += 4
    for j in 0..<bytes.length() {
      argv[offset + j] = bytes[j]
    }
    offset += bytes.length()
  }
  defer (if stdout is Some(p) { p.after_spawn() })
  let stdout = match stdout {
    Some(pipe) => pipe.fd()
    None => @fd_util.invalid_fd
  }
  let handle = spawn_process(
    argv,
    argv_len,
    argv_bytes.length(),
    @fd_util.invalid_fd,
    stdout,
    @fd_util.invalid_fd,
  )
  if handle < 0 {
    @os_error.check_errno(context)
  }
  handle
}

///|
fn write_i32_le(buf : FixedArray[Byte], offset : Int, value : Int) -> Unit {
  buf[offset] = (value & 0xff).to_byte()
  buf[offset + 1] = ((value >> 8) & 0xff).to_byte()
  buf[offset + 2] = ((value >> 16) & 0xff).to_byte()
  buf[offset + 3] = ((value >> 24) & 0xff).to_byte()
}
