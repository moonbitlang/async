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
extern "C" fn find_ipv6_test_interface() -> UInt = "moonbitlang_async_find_ipv6_test_interface"

///|
let test_interface_index : UInt = {
  let index = find_ipv6_test_interface()
  if index is 0 {
    abort("cannot find localhost adaptor, or localhost does not support IPv6")
  }
  index
}

///|
let test_interface : String = @socket.if_indextoname(
  test_interface_index,
  context="fetch name of localhost adaptor",
) catch {
  err => abort(err.to_string())
}
