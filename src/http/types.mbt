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
pub(all) struct Request {
  meth : RequestMethod
  path : String
  headers : Map[String, String]
}

///|
pub(all) struct Response {
  code : Int
  reason : String
  headers : Map[String, String]
}

///|
/// `Body` is a trait for types that can be used as HTTP body.
/// Currently `Bytes` (for binary data), `String` (UTF8 encoded),
/// and `Json` (also UTF8 encoded) are supported.
trait Body {
  async to_bytes(Self) -> Bytes
}

///|
pub impl Body for Bytes with to_bytes(self) {
  self
}

///|
pub impl Body for String with to_bytes(self) {
  @encoding/utf8.encode(self)
}

///|
pub impl Body for Json with to_bytes(self) {
  self.stringify() |> @encoding/utf8.encode
}

// ==============================================================================
// internal node: the `Body` trait serves two purpose.
// When the user is sending data, we use `to_bytes` to convert user data to binary.
// When the user is receiving data, raw data is always represented as raw binary,
// so `&Body` always internally hold a `Bytes`,
// and the user may use these helpers below to convert them to different format.
//
// Technically we should use two types for these two purposes,
// but that would mean two different names, instead of the simple `Body`.
// So currently we take this rather hacky approach for simplicify of API.
// ==============================================================================

///|
/// Extract the raw binary data in request/response body.
pub async fn &Body::binary(self : &Body) -> Bytes {
  self.to_bytes()
}

///|
/// Extract request/response body as a UTF8 encoded string.
///
/// Calling this method will cause string decoding,
/// so user should avoid calling `.text()` more than once.
pub async fn &Body::text(self : &Body) -> String {
  self.to_bytes() |> @encoding/utf8.decode
}

///|
/// Extract request/response body as a UTF8 encoded JSON.
///
/// Calling this method will cause string decoding and json parsing,
/// so user should avoid calling `.json()` more than once.
pub async fn &Body::json(self : &Body) -> Json {
  self.to_bytes() |> @encoding/utf8.decode |> @json.parse
}
