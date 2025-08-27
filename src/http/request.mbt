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
pub(all) enum RequestProtocol {
  Http
  Https
}

///|
async fn[Conn : @io.Reader + @io.Writer] make_request(
  conn : Conn,
  path : Bytes,
  headers~ : Array[Header],
) -> (Response, Bytes) raise {
  send_request(conn, { meth: Get, path, headers }, Empty)
  let reader = Reader::new(conn)
  let response = reader.read_response()
  (response, reader.read_all())
}

///|
/// Perform a HTTP network request to `uri`,
/// which should be a URI without the protocol part.
/// The HTTP response message and the whole response body will be returned.
///
/// The protocol can be specified via `protocol`, which is `Https` by default.
/// By default the standard port number of `protocol` is used,
/// but this can be overriden by explicitly passing `port`.
///
/// Additional HTTP headers can be passed via `headers`.
/// The ownership of `headers` will be transferred to `request`,
/// so `headers` should be a temporary array.
/// The following headers is automatically set by `request`,
/// and must not be specified in `headers`:
/// 
/// - Host
/// - Content-Length, Transfer-Encoding
pub async fn request(
  uri : Bytes,
  headers~ : Array[Header] = [],
  protocol~ : RequestProtocol = Https,
  port~ : Int = match protocol {
    Http => 80
    Https => 443
  },
) -> (Response, Bytes) raise {
  let (host, path) = for i = 0; i < uri.length(); i = i + 1 {
    if uri[i] == '/' {
      break (uri[:i].to_bytes(), uri[i:].to_bytes())
    }
  } else {
    (uri, "/")
  }
  let path = if path == "" { b"/" } else { path }
  let conn = @socket.TCP::connect_to_host(host, port~)
  defer conn.close()
  headers.push(Header("Host", host))
  match protocol {
    Http => make_request(conn, path, headers~)
    Https => {
      let conn = @tls.TLS::client(conn, host~)
      defer conn.close()
      try make_request(conn, path, headers~) catch {
        err => {
          if not(err is (@tls.OpenSSLError(_) | @tls.ConnectionClosed)) {
            @async.with_timeout(1000, () => conn.shutdown())
          }
          raise err
        }
      } noraise {
        result => {
          @async.with_timeout(1000, () => conn.shutdown())
          result
        }
      }
    }
  }
}
