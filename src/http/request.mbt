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
  uri : Bytes,
  meth : RequestMethod,
  headers : Array[Header],
  body : Body,
  port? : Int,
) -> (Response, Bytes) raise {
  guard uri.find("://") is Some(protocol_len) else { raise InvalidFormat }
  let protocol = match uri[:protocol_len] {
    "http" => Http
    "https" => Https
    protocol => raise UnsupportedProtocol(@bytes_util.ascii_to_string(protocol))
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
    (uri[:i].to_bytes(), uri[i:].to_bytes())
  } else {
    (uri.to_bytes(), "/")
  }
  let path = if path == "" { b"/" } else { path }
  let client = Client::connect(host, headers~, protocol~, port~)
  defer client.close()
  let response = client.request(meth, path, body)
  let body = client.read_all()
  (response, body)
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
#alias(request, deprecated)
pub async fn get(
  uri : Bytes,
  headers? : Array[Header] = [],
  port? : Int,
) -> (Response, Bytes) raise {
  perform_request(uri, Get, headers, Empty, port?)
}

///|
/// Similar to `get`, but performs a `PUT` request instead.
pub async fn put(
  uri : Bytes,
  content : Bytes,
  headers? : Array[Header] = [],
  port? : Int,
) -> (Response, Bytes) raise {
  perform_request(uri, Put, headers, Fixed(content), port?)
}

///|
/// Similar to `get`, but performs a `POST` request instead.
pub async fn post(
  uri : Bytes,
  content : Bytes,
  headers? : Array[Header] = [],
  port? : Int,
) -> (Response, Bytes) raise {
  perform_request(uri, Post, headers, Fixed(content), port?)
}
