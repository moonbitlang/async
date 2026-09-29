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
test "method names preserve case and recognize named methods" {
  assert_eq(@http.RequestMethod::from_string("HEAD"), @http.Head)
  assert_eq(@http.Head.as_string(), "HEAD")
  for name in ["PROPFIND", "head", "!#$%&'*+-.^_`|~0123456789"] {
    let meth = @http.RequestMethod::from_string(name)
    assert_eq(meth, @http.Extension(name))
    assert_eq(meth.as_string(), name)
  }
}

///|
test "invalid method tokens" {
  for name in ["", "X Y", "X\r\nY", "X/Y", "方法"] {
    try @http.RequestMethod::from_string(name) catch {
      @http.InvalidMethod => ()
    } noraise {
      _ => fail("accepted invalid method: \{name.escape()}")
    }
  }
}
