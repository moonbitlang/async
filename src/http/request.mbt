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

/// HTTP protocol type specifying whether to use HTTP or HTTPS.
/// Used to determine connection security and default port.
pub(all) enum Protocol {
  /// Plain HTTP protocol (default port 80)
  Http
  /// Secure HTTPS protocol with TLS encryption (default port 443)
  Https
}

/// Get the default port number for a given HTTP protocol.
/// Returns 80 for HTTP and 443 for HTTPS.
pub fn Protocol::default_port(p : Protocol) -> Int {
  match p {
    Http => 80
    Https => 443
  }
}

/// Error type for URI parsing failures.
/// Represents various issues that can occur when parsing URIs.
pub suberror URIParseError {
  /// The URI format is invalid or malformed
  InvalidFormat
  /// The protocol scheme is not supported (only http and https are supported)
  UnsupportedProtocol(String)
} derive(Show)

/// Internal function to perform HTTP requests.
/// This is the core implementation used by the convenience functions like get, post, etc.
async fn perform_request(
  uri : String,
  meth : RequestMethod,
  headers : Map[String, String],
  body : &@io.Data,
  port? : Int,
) -> (Response, &@io.Data) {
  guard uri.find("://") is Some(protocol_len) else { raise InvalidFormat }
  let protocol = match uri[:protocol_len] {
    "http" => Http
    "https" => Https
    protocol => raise UnsupportedProtocol(protocol.to_string())
  }
  let port = match port {
    Some(port) => port
    None =>
      match protocol {
        Http => 80
        Https => 443
      }
  }
  let uri = uri[protocol_len + 3:]
  let (host, path) = if uri.find("/") is Some(i) {
    (uri[:i].to_string(), uri[i:].to_string())
  } else {
    (uri.to_string(), "/")
  }
  let path = if path == "" { "/" } else { path }
  let client = Client::connect(host, headers~, protocol~, port~)
  defer client.close()
  client..request(meth, path)..write(body)
  let response = client.end_request()
  (response, client.read_all())
}

/// Perform a HTTP GET request to the specified URI.
/// 
/// This is a convenience function for making simple GET requests.
/// Supported protocols are `http://` and `https://`.
/// Returns a tuple containing the HTTP response and the complete response body.
///
/// # Parameters
/// - `uri`: The complete URI to request (e.g., "https://example.com/api/data")
/// - `headers`: Optional additional HTTP headers to include in the request
/// - `port`: Optional port number to connect to (defaults to protocol standard port)
/// - `body`: Optional request body data (defaults to empty for GET requests)
///
/// # Example
/// ```moonbit
/// let (response, body) = @http.get("https://api.github.com/users/octocat")
/// if response.code == 200 {
///   println(body.text())
/// }
/// ```
pub async fn get(
  uri : String,
  headers? : Map[String, String] = {},
  port? : Int,
  body? : &@io.Data = b"",
) -> (Response, &@io.Data) {
  perform_request(uri, Get, headers, body, port?)
}

/// Perform a HTTP PUT request to the specified URI.
/// 
/// Similar to `get`, but performs a PUT request with the provided content.
/// PUT requests are typically used to create or update resources on the server.
///
/// # Parameters
/// - `uri`: The complete URI to request
/// - `content`: The data to send as the request body
/// - `headers`: Optional additional HTTP headers
/// - `port`: Optional port number to connect to
///
/// # Example
/// ```moonbit
/// let data = b"{'name': 'John', 'age': 30}"
/// let headers = Map::from_array([("Content-Type", "application/json")])
/// let (response, body) = @http.put("https://api.example.com/users/1", data, headers~)
/// ```
pub async fn put(
  uri : String,
  content : &@io.Data,
  headers? : Map[String, String] = {},
  port? : Int,
) -> (Response, &@io.Data) {
  perform_request(uri, Put, headers, content, port?)
}

/// Perform a HTTP POST request to the specified URI.
/// 
/// Similar to `get`, but performs a POST request with the provided content.
/// POST requests are typically used to submit data to be processed by the server.
///
/// # Parameters
/// - `uri`: The complete URI to request
/// - `content`: The data to send as the request body
/// - `headers`: Optional additional HTTP headers
/// - `port`: Optional port number to connect to
///
/// # Example
/// ```moonbit
/// let form_data = b"username=alice&password=secret"
/// let headers = Map::from_array([("Content-Type", "application/x-www-form-urlencoded")])
/// let (response, body) = @http.post("https://api.example.com/login", form_data, headers~)
/// ```
pub async fn post(
  uri : String,
  content : &@io.Data,
  headers? : Map[String, String] = {},
  port? : Int,
) -> (Response, &@io.Data) {
  perform_request(uri, Post, headers, content, port?)
}
