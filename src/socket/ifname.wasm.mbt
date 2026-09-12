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
#unsafe_skip_stub_check
#borrow(name)
fn if_nametoindex_ffi(
  name : @os_string.OsString,
  name_len? : Int = name.to_string().length(),
) -> UInt = "moonbitlang/async" "socket/if_nametoindex"

///|
#unsafe_skip_stub_check
fn if_indextoname_ffi(index : UInt) -> @c_buffer.Buffer = "moonbitlang/async" "socket/if_indextoname"

///|
#doc(hidden)
#internal(internal, "for internal use only")
pub fn if_nametoindex(name : StringView, context~ : String) -> UInt raise {
  let os_name = @os_string.encode(name)
  let index = if_nametoindex_ffi(os_name)
  if index is 0 {
    @os_error.check_errno("\{context}: if_nametoindex(\{name.escape()})")
  }
  index
}

///|
#doc(hidden)
#internal(internal, "for internal use only")
pub fn if_indextoname(index : UInt, context~ : String) -> String raise {
  let name = if_indextoname_ffi(index)
  if name.is_null() {
    @os_error.check_errno("\{context}: if_indextoname(\{index})")
  }
  defer name.free()
  @os_string.decode(name)
}
