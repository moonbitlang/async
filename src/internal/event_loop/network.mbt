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
#external
pub type AddrInfo

///|
#cfg(not(platform="windows"))
extern "C" fn gai_strerror(code : Int) -> @c_buffer.Buffer = "gai_strerror"

///|
#cfg(not(platform="windows"))
fn gai_error_to_string(code : Int) -> String {
  @os_string.decode(gai_strerror(code))
}

///|
#cfg(platform="windows")
fn gai_error_to_string(code : Int) -> String {
  @os_error.errno_to_string(code)
}

///|
pub async fn getaddrinfo(
  host : StringView,
  context~ : String,
) -> Result[AddrInfo, String] {
  @coroutine.check_cancellation()
  let host_bytes = @os_string.encode(host)
  let spec = OperationSpec::getaddrinfo(host_bytes)
  let mut result = Err("")
  let mut terminated = false
  defer {
    terminated = true
  }
  // `getaddrinfo` cannot be cancelled,
  // but it always does not have any critical side effect.
  // So our strategy here is to keep `getaddrinfo` running on cancellation,
  // let a background task wait for its completion and perform cleanup,
  // while not waiting for the result in the main task
  try
    @coroutine.spawn(() => {
      let job = perform_operation(spec, context~) catch {
        @os_error.OSError(errno, context~) =>
          raise @os_error.OSError(errno, context="\{context}: \{host.escape()}")
        err => raise err
      }
      defer job.free()
      // if the outer `getaddrinfo` call already terminated,
      // we should not extract the result from the job,
      // instead we should let `job.free` free the result.
      guard !terminated else { return }
      let ret = job.ret()
      if ret != 0 {
        result = Err(gai_error_to_string(ret))
      } else {
        result = Ok(job.getaddrinfo_result())
      }
    }).wait()
  catch {
    _ if result is Ok(_) =>
      // corner case: if the job happens to complete at the same tick as cancellation,
      // as long as `get_getaddrinfo_result` is called,
      // we should treat `getaddrinfo` as successful anyway,
      // otherwise the result will leak
      return result
    err => raise err
  } noraise {
    _ => result
  }
}

///|
pub async fn IoHandle::bind(
  handle : IoHandle,
  addr : Bytes,
  context~ : String,
) -> Unit {
  @coroutine.check_cancellation()
  let job = perform_operation(OperationSpec::bind(handle.fd, addr), context~)
  defer job.free()
}
