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
#cfg(target="native")
extern "C" fn Job::run_sync_ffi(self : Job) -> Unit = "moonbit_rt_run_job_sync"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn JobHandle::run_sync(self : JobHandle) -> Unit = "moonbitlang/async" "thread_pool/run_job"

///|
#cfg(target="wasm")
fn Job::run_sync_ffi(self : Job) -> Unit {
  self.handle.run_sync()
}

///|
// Run a fresh job on the calling thread, without entering the event loop or
// submitting a completion. The caller must free the job after consuming its
// results and must not submit it again. Blocking jobs also block cancellation
// and other coroutines; use this only where synchronous execution is intended.
// Wasm output copying still requires exported memory, so this is not a way to
// perform memory-writing operations during a Wasm start section.
fn Job::run_sync(job : Job, context~ : String) -> Int32 raise {
  job.run_sync_ffi()
  if job.err() is err && err > 0 {
    raise @os_error.OSError(err, context~)
  }
  job.copy_output()
  job.ret()
}

///|
test "synchronous job returns a scalar without an event loop" {
  let job = Job::access(@os_string.encode("."), Exist)
  defer job.free()
  assert_eq(job.run_sync(context="sync access"), 0)
}

///|
test "synchronous job copies the existing stat result" {
  let buf = FixedArray::make(16, b'\xff')
  let job = Job::statx(
    @os_string.encode("."),
    STAT_FILE_KIND,
    buf,
    buf.length(),
    parent=@fd_util.invalid_fd,
    follow_symlink=true,
  )
  defer job.free()
  assert_eq(job.run_sync(context="sync stat"), 0)
  guard buf is [u32le(16), u32le(mask), i64le(kind)] else {
    fail("invalid stat result")
  }
  assert_eq(mask, STAT_FILE_KIND)
  assert_eq(@fd_util.FileKind::from_int(kind.to_int()), Directory)
}

///|
test "synchronous job preserves errors" {
  let buf = FixedArray::make(16, b'\xaa')
  let job = Job::statx(
    @os_string.encode(""),
    STAT_FILE_KIND,
    buf,
    buf.length(),
    parent=@fd_util.invalid_fd,
    follow_symlink=true,
  )
  defer job.free()
  let failed = try job.run_sync(context="sync stat failure") catch {
    @os_error.OSError(_, context~) => {
      assert_eq(context, "sync stat failure")
      true
    }
    err => raise err
  } noraise {
    _ => false
  }
  assert_true(failed)
  assert_true(job.err() > 0)
  assert_eq(job.ret(), -1)
}
