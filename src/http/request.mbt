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
pub(all) enum Protocol {
  Http
  Https
}

///|
pub fn Protocol::default_port(p : Protocol) -> Int {
  match p {
    Http => 80
    Https => 443
  }
}

///|
pub suberror URIParseError {
  InvalidFormat
  UnsupportedProtocol(String)
} derive(Show)

///|
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

///|
/// Perform a HTTP `GET` request to `uri`.
/// Supported protocols are `http://` and `https://`.
/// The HTTP response message and the whole response body will be returned.
///
/// `port` is the port number to connect to.
/// By default it is the standard port for the specified protocol.
///
/// See `Client::request` for more details.
pub async fn get(
  uri : String,
  headers? : Map[String, String] = {},
  port? : Int,
  body? : &@io.Data = b"",
) -> (Response, &@io.Data) {
  perform_request(uri, Get, headers, body, port?)
}

///|
/// Similar to `get`, but performs a `PUT` request instead.
pub async fn put(
  uri : String,
  content : &@io.Data,
  headers? : Map[String, String] = {},
  port? : Int,
) -> (Response, &@io.Data) {
  perform_request(uri, Put, headers, content, port?)
}

///|
/// Similar to `get`, but performs a `POST` request instead.
pub async fn post(
  uri : String,
  content : &@io.Data,
  headers? : Map[String, String] = {},
  port? : Int,
) -> (Response, &@io.Data) {
  perform_request(uri, Post, headers, content, port?)
}
