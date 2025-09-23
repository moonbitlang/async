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
pub(all) enum RequestMethod {
  Get
  Head
  Post
  Put
  Delete
  Connect
  Options
  Trace
  Patch
} derive(Show)

///|
pub(all) struct Header(String, String)

///|
pub(all) struct Request {
  meth : RequestMethod
  path : String
  headers : Array[Header]
}

///|
pub(all) struct Response {
  code : Int
  reason : String
  headers : Array[Header]
}

///|
/// `Body` is a trait for types that can be used as HTTP body.
/// Currently `Bytes` (for binary data), `String` (UTF8 encoded),
/// and `Json` (also UTF8 encoded) are supported.
trait Body {
  async read(Reader) -> Self
  async write(Self, Sender) -> Unit
}

///|
pub impl Body for Bytes with read(reader) {
  reader.read_all()
}

///|
pub impl Body for Bytes with write(self, sender) {
  sender.write(self)
}

///|
pub impl Body for String with read(reader) {
  @encoding/utf8.decode(reader.read_all())
}

///|
pub impl Body for String with write(self, sender) {
  sender.write_string(self, encoding=UTF8)
}

///|
pub impl Body for Json with read(reader) {
  @encoding/utf8.decode(reader.read_all()) |> @json.parse
}

///|
pub impl Body for Json with write(self, sender) {
  sender.write_string(self.stringify(), encoding=UTF8)
}
