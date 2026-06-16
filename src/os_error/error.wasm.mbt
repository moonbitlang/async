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
pub fn get_errno() -> Int = "moonbit_v0" "os_error/get_errno"

///|
#internal(internal, "for internal use only")
pub fn errno_to_string(errno : Int) -> String {
  // PR1 only needs numeric errno reporting from `moonrun`; host-side errno
  // stringification should be added with the broader os_error/fs surface.
  "errno \{errno}"
}

///|
pub(all) suberror OSError {
  OSError(Int, context~ : String)
} derive(ToJson)

///|
pub impl Show for OSError with fn output(self, logger) -> Unit {
  let OSError(errno, context~) = self
  let msg = "\{context}: \{errno_to_string(errno)}"
  logger <+ "OSError(\{to_repr(msg)})"
}

///|
pub fn check_errno(context : String) -> Unit raise OSError {
  let err_code = get_errno()
  if err_code != 0 {
    raise OSError(err_code, context~)
  }
}
