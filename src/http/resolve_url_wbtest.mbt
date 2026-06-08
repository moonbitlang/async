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
test "resolve_url" {
  fn to_owned(result : (_, _, StringView)) {
    let (a, b, c) = result
    (a, b, c.to_owned())
  }
  debug_inspect(
    try to_owned(resolve_url("http://www.example.org")) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Ok((Http, "www.example.org", "/"))
    ),
  )
  debug_inspect(
    try to_owned(resolve_url("http://www.example.org/path/to")) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Ok((Http, "www.example.org", "/path/to"))
    ),
  )
  debug_inspect(
    try
      to_owned(resolve_url("https://www.example.org/path/to?search=q"))
    catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Ok((Https, "www.example.org", "/path/to?search=q"))
    ),
  )
  debug_inspect(
    try to_owned(resolve_url("ftp://www.example.org")) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Err(UnsupportedProtocol("ftp"))
    ),
  )
  debug_inspect(
    try to_owned(resolve_url("http://www.example.org:10042")) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Ok((Http, "www.example.org:10042", "/"))
    ),
  )
  debug_inspect(
    try to_owned(resolve_url("http://www.example.org:10042/path")) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Ok((Http, "www.example.org:10042", "/path"))
    ),
  )
}

///|
test "resolve_host" {
  fn to_owned(result : (StringView, _)) {
    let (a, b) = result
    (a.to_owned(), b)
  }

  debug_inspect(
    try to_owned(resolve_host("www.example.org", protocol=Http)) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Ok(("www.example.org", 80))
    ),
  )
  debug_inspect(
    try to_owned(resolve_host("www.example.org", protocol=Https)) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Ok(("www.example.org", 443))
    ),
  )
  debug_inspect(
    try to_owned(resolve_host("www.example.org:42", protocol=Http)) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Ok(("www.example.org", 42))
    ),
  )
  debug_inspect(
    try to_owned(resolve_host("www.example.org:42", protocol=Https)) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Ok(("www.example.org", 42))
    ),
  )
  debug_inspect(
    try to_owned(resolve_host("www.example.org:0", protocol=Https)) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Err(InvalidFormat)
    ),
  )
  debug_inspect(
    try to_owned(resolve_host("www.example.org:100042", protocol=Https)) catch {
      e => Result::Err(e)
    } noraise {
      value => Ok(value)
    },
    content=(
      #|Err(InvalidFormat)
    ),
  )
}
