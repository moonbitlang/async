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
struct Process(Int)

///|
pub fn Process::pid(self : Process) -> Int {
  self.0
}

///|
pub fn Process::from_pid(pid : Int, context~ : String) -> Process {
  ignore(context)
  Process(pid)
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
#borrow(argv)
fn spawn_process_raw(
  argv : FixedArray[Byte],
  argv_len : Int,
  argc : Int,
  stdin : @fd_util.Fd,
  stdout : @fd_util.Fd,
  stderr : @fd_util.Fd,
) -> Int {
  spawn_process_ffi(
    @wasm_ffi.byte_array_to_ptr(argv),
    argv_len,
    argc,
    stdin,
    stdout,
    stderr,
  )
}

///|
pub async fn spawn(
  path : @os_string.OsString,
  args : FixedArray[@os_string.OsString?],
  env~ : FixedArray[@os_string.OsString?],
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  cwd~ : @os_string.OsString?,
  context~ : String,
) -> Process {
  ignore(env)
  ignore(cwd)
  let argv_bufs : Array[Bytes] = []
  argv_bufs.push(@utf8.encode(path.to_string()))
  let mut argv_len = 4 + argv_bufs[0].length()
  for i in 0..<args.length() {
    if args[i] is Some(arg) {
      let bytes = @utf8.encode(arg.to_string())
      argv_len += 4 + bytes.length()
      argv_bufs.push(bytes)
    }
  }
  let argv = FixedArray::make(argv_len, b'\x00')
  let mut offset = 0
  for i in 0..<argv_bufs.length() {
    let bytes = argv_bufs[i]
    write_i32_le(argv, offset, bytes.length())
    offset += 4
    for j in 0..<bytes.length() {
      argv[offset + j] = bytes[j]
    }
    offset += bytes.length()
  }
  let handle = spawn_process_raw(
    argv,
    argv_len,
    argv_bufs.length(),
    stdin,
    stdout,
    stderr,
  )
  if handle < 0 {
    @os_error.check_errno(context)
  }
  Process(handle)
}

///|
fn write_i32_le(buf : FixedArray[Byte], offset : Int, value : Int) -> Unit {
  buf[offset] = (value & 0xff).to_byte()
  buf[offset + 1] = ((value >> 8) & 0xff).to_byte()
  buf[offset + 2] = ((value >> 16) & 0xff).to_byte()
  buf[offset + 3] = ((value >> 24) & 0xff).to_byte()
}

///|
pub async fn Process::wait_pid(self : Process, context~ : String) -> Int {
  wait_process_handle(self.0, context~)
}

///|
pub async fn wait_process_handle(handle : Int, context~ : String) -> Int {
  perform_job_in_worker(Job::wait_for_process(handle), context~)
}
