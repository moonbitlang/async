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
} derive(Debug, Eq, Compare, Hash, ToJson)

///|
pub(all) struct Request {
  meth : RequestMethod
  path : String
  headers : Map[String, String]
} derive(Debug, ToJson)

///|
pub(all) struct Response {
  code : Int
  reason : String
  headers : Map[String, String]
  /// The list of cookies specified in `Set-Cookie` headers.
  ///
  /// JS backend note: browsers forbid JS code from accessing raw cookie values,
  /// so this field is always empty on JS backend.
  cookies : Array[Cookie]
} derive(Debug, ToJson)

///|
pub struct Cookie {
  name : String
  value : String
  path : String?
  expires_raw : String?
  max_age : Int64?
  domain : String?
  secure : Bool
  http_only : Bool
  extensions : Array[String]
} derive(Debug, ToJson)
