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
/// HPACK static table per RFC 7541 Appendix A.
/// 61 entries, 0-indexed in the array but HPACK uses 1-based indexing.
let static_table : Array[(String, String)] = [
  (":authority", ""),
  (":method", "GET"),
  (":method", "POST"),
  (":path", "/"),
  (":path", "/index.html"),
  (":scheme", "http"),
  (":scheme", "https"),
  (":status", "200"),
  (":status", "204"),
  (":status", "206"),
  (":status", "304"),
  (":status", "400"),
  (":status", "404"),
  (":status", "500"),
  ("accept-charset", ""),
  ("accept-encoding", "gzip, deflate"),
  ("accept-language", ""),
  ("accept-ranges", ""),
  ("accept", ""),
  ("access-control-allow-origin", ""),
  ("age", ""),
  ("allow", ""),
  ("authorization", ""),
  ("cache-control", ""),
  ("content-disposition", ""),
  ("content-encoding", ""),
  ("content-language", ""),
  ("content-length", ""),
  ("content-location", ""),
  ("content-range", ""),
  ("content-type", ""),
  ("cookie", ""),
  ("date", ""),
  ("etag", ""),
  ("expect", ""),
  ("expires", ""),
  ("from", ""),
  ("host", ""),
  ("if-match", ""),
  ("if-modified-since", ""),
  ("if-none-match", ""),
  ("if-range", ""),
  ("if-unmodified-since", ""),
  ("last-modified", ""),
  ("link", ""),
  ("location", ""),
  ("max-forwards", ""),
  ("proxy-authenticate", ""),
  ("proxy-authorization", ""),
  ("range", ""),
  ("referer", ""),
  ("refresh", ""),
  ("retry-after", ""),
  ("server", ""),
  ("set-cookie", ""),
  ("strict-transport-security", ""),
  ("transfer-encoding", ""),
  ("user-agent", ""),
  ("vary", ""),
  ("via", ""),
  ("www-authenticate", ""),
]

///|
/// Reverse lookup: name -> (value -> 1-based index).
let static_table_by_name_value : Map[String, Map[String, Int]] = {
  let m : Map[String, Map[String, Int]] = {}
  for i = 0; i < static_table.length(); i = i + 1 {
    let (name, value) = static_table[i]
    let index = i + 1
    match m.get(name) {
      Some(inner) =>
        // Only store the first occurrence for each (name, value) pair
        if not(inner.contains(value)) {
          inner[value] = index
        }
      None => {
        let inner : Map[String, Int] = {}
        inner[value] = index
        m[name] = inner
      }
    }
  }
  m
}

///|
/// Reverse lookup: name -> first 1-based index with that name.
let static_table_by_name : Map[String, Int] = {
  let m : Map[String, Int] = {}
  for i = 0; i < static_table.length(); i = i + 1 {
    let (name, _) = static_table[i]
    let index = i + 1
    if not(m.contains(name)) {
      m[name] = index
    }
  }
  m
}
