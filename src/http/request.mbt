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
async fn perform_request(
  uri : Bytes,
  meth : RequestMethod,
  headers : Array[Header],
  body : Body,
  protocol~ : Protocol,
  port~ : Int,
) -> (Response, Bytes) raise {
  let (host, path) = for i = 0; i < uri.length(); i = i + 1 {
    if uri[i] == '/' {
      break (uri[:i].to_bytes(), uri[i:].to_bytes())
    }
  } else {
    (uri, "/")
  }
  let path = if path == "" { b"/" } else { path }
  let client = Client::connect(host, headers~, protocol~, port~)
  defer client.close()
  let response = client.request(meth, path, body)
  let body = client.read_all()
  client.shutdown()
  (response, body)
}

///|
/// Perform a HTTP `GET` request to `uri`,
/// which should be a URI without the protocol part.
/// The HTTP response message and the whole response body will be returned.
///
/// The protocol can be specified via `protocol`, which is `Https` by default.
/// By default the standard port number of `protocol` is used,
/// but this can be overriden by explicitly passing `port`.
///
/// See `Client::request` for more details.
#alias(request, deprecated)
pub async fn get(
  uri : Bytes,
  headers? : Array[Header] = [],
  protocol? : Protocol = Https,
  port? : Int = protocol.default_port(),
) -> (Response, Bytes) raise {
  perform_request(uri, Get, headers, Empty, protocol~, port~)
}

///|
/// Similar to `get`, but performs a `PUT` request instead.
pub async fn put(
  uri : Bytes,
  content : Bytes,
  headers? : Array[Header] = [],
  protocol? : Protocol = Https,
  port? : Int = protocol.default_port(),
) -> (Response, Bytes) raise {
  perform_request(uri, Put, headers, Fixed(content), protocol~, port~)
}

///|
/// Similar to `get`, but performs a `POST` request instead.
pub async fn post(
  uri : Bytes,
  content : Bytes,
  headers? : Array[Header] = [],
  protocol? : Protocol = Https,
  port? : Int = protocol.default_port(),
) -> (Response, Bytes) raise {
  perform_request(uri, Post, headers, Fixed(content), protocol~, port~)
}
