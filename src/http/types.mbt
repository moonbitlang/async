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

/// HTTP request methods supported by the client and server.
/// This enum represents the standard HTTP methods as defined in RFC 7231.
pub(all) enum RequestMethod {
  /// HTTP GET method - retrieve data from the server
  Get
  /// HTTP HEAD method - like GET but returns only headers
  Head
  /// HTTP POST method - submit data to be processed
  Post
  /// HTTP PUT method - create or update a resource
  Put
  /// HTTP DELETE method - delete a resource
  Delete
  /// HTTP CONNECT method - establish a tunnel to the server
  Connect
  /// HTTP OPTIONS method - return allowed methods for a resource
  Options
  /// HTTP TRACE method - perform a message loop-back test
  Trace
  /// HTTP PATCH method - apply partial modifications to a resource
  Patch
} derive(Show, Eq)

/// Represents an HTTP request with method, path, and headers.
/// This structure is used by both client and server to represent
/// incoming or outgoing HTTP requests.
pub(all) struct Request {
  /// The HTTP method for this request
  meth : RequestMethod
  /// The request path (e.g., "/api/users")
  path : String
  /// HTTP headers as key-value pairs
  headers : Map[String, String]
}

/// Represents an HTTP response with status code, reason phrase, and headers.
/// This structure is used to represent HTTP responses from servers.
pub(all) struct Response {
  /// HTTP status code (e.g., 200, 404, 500)
  code : Int
  /// HTTP reason phrase (e.g., "OK", "Not Found", "Internal Server Error")
  reason : String
  /// HTTP headers as key-value pairs
  headers : Map[String, String]
}
