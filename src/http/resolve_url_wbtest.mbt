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
  debug_inspect(
    try? resolve_url("http://www.example.org"),
    content=(
      #|Ok((Http, "www.example.org", "www.example.org", 80, "/"))
    ),
  )
  debug_inspect(
    try? resolve_url("http://www.example.org/path/to"),
    content=(
      #|Ok((Http, "www.example.org", "www.example.org", 80, "/path/to"))
    ),
  )
  debug_inspect(
    try? resolve_url("https://www.example.org/path/to?search=q"),
    content=(
      #|Ok(
      #|  (
      #|    Https,
      #|    "www.example.org",
      #|    "www.example.org",
      #|    443,
      #|    "/path/to?search=q",
      #|  ),
      #|)
    ),
  )
  debug_inspect(
    try? resolve_url("ftp://www.example.org"),
    content=(
      #|Err(UnsupportedProtocol("ftp"))
    ),
  )
  debug_inspect(
    try? resolve_url("http://www.example.org:10042"),
    content=(
      #|Ok((Http, "www.example.org:10042", "www.example.org", 10042, "/"))
    ),
  )
  debug_inspect(
    try? resolve_url("http://www.example.org:10042/path"),
    content=(
      #|Ok((Http, "www.example.org:10042", "www.example.org", 10042, "/path"))
    ),
  )
  debug_inspect(
    try? resolve_url("http://www.example.org:80"),
    content=(
      #|Ok((Http, "www.example.org:80", "www.example.org", 80, "/"))
    ),
  )
  debug_inspect(
    try? resolve_url("https://www.example.org:443"),
    content=(
      #|Ok((Https, "www.example.org:443", "www.example.org", 443, "/"))
    ),
  )
  debug_inspect(
    try? resolve_url("http://www.example.org:0"),
    content="Err(InvalidFormat)",
  )
  debug_inspect(
    try? resolve_url("http://www.example.org:100042"),
    content="Err(InvalidFormat)",
  )
}
