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
/// Raised when a method name is invalid, or an extension uses a standard method name.
pub suberror InvalidMethod derive(Debug, ToJson)

///|
/// Parse a HTTP method name. Method names are case sensitive.
/// Standard method names return the corresponding constructor,
/// other valid names return `Extension`.
/// Raises `InvalidMethod` if the name is empty or contains invalid characters.
pub fn RequestMethod::from_string(
  name : StringView,
) -> RequestMethod raise InvalidMethod {
  guard !name.is_empty() else { raise InvalidMethod }
  for c in name.code_units() {
    guard is_token_char(c) else { raise InvalidMethod }
  }
  match name {
    "GET" => Get
    "HEAD" => Head
    "POST" => Post
    "PUT" => Put
    "DELETE" => Delete
    "CONNECT" => Connect
    "OPTIONS" => Options
    "TRACE" => Trace
    "PATCH" => Patch
    _ => Extension(name.to_owned())
  }
}

///|
/// Get the name of a HTTP method.
/// For `Extension`, the name is returned as is, without validation.
pub fn RequestMethod::as_string(self : RequestMethod) -> String {
  match self {
    Get => "GET"
    Head => "HEAD"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
    Connect => "CONNECT"
    Options => "OPTIONS"
    Trace => "TRACE"
    Patch => "PATCH"
    Extension(name) => name
  }
}

///|
fn RequestMethod::validate(self : RequestMethod) -> Unit raise InvalidMethod {
  if self is Extension(name) {
    guard RequestMethod::from_string(name) is Extension(_) else {
      raise InvalidMethod
    }
  }
}
