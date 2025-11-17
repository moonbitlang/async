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
/// HTTP proxy configuration
enum Proxy {
  ForHttp(String, Int)
  ForHttps(String, Int)
  ForAll(String, Int)
  Custom(http~ : (String, Int), https~ : (String, Int))
}

///|
/// Create a proxy configuration for HTTP requests only
pub fn Proxy::http(host : String, port~ : Int) -> Proxy {
  ForHttp(host, port)
}

///|
/// Create a proxy configuration for HTTPS requests only
pub fn Proxy::https(host : String, port~ : Int) -> Proxy {
  ForHttps(host, port)
}

///|
/// Create a proxy configuration for all protocols (HTTP and HTTPS)
pub fn Proxy::all(host : String, port~ : Int) -> Proxy {
  ForAll(host, port)
}

///|
/// Create a custom proxy configuration with different proxies for HTTP and HTTPS
pub fn Proxy::custom(
  http_host : String,
  http_port~ : Int,
  https_host : String,
  https_port~ : Int,
) -> Proxy {
  Custom(http=(http_host, http_port), https=(https_host, https_port))
}

///|
fn Proxy::should_use(self : Proxy, protocol : Protocol) -> (String, Int)? {
  match (self, protocol) {
    (ForHttp(host, port), Http) => Some((host, port))
    (ForHttps(host, port), Https) => Some((host, port))
    (ForAll(host, port), _) => Some((host, port))
    (Custom(http~, ..), Http) => Some(http)
    (Custom(https~, ..), Https) => Some(https)
    _ => None
  }
}

///|
/// Error raised when proxy connection fails
pub suberror ProxyConnectError {
  ProxyConnectionFailed(String)
  ProxyAuthenticationRequired
} derive(Show)

///|
async fn connect_through_proxy(
  host : String,
  port : Int,
  target_host : String,
  target_port : Int,
) -> @socket.Tcp {
  let proxy_conn = @socket.Tcp::connect_to_host(host, port~)
  let request = "CONNECT \{target_host}:\{target_port} HTTP/1.1\r\nHost: \{target_host}:\{target_port}\r\n\r\n"
  proxy_conn.write(request)
  let reader = Reader::new(proxy_conn)
  let response = reader.read_response() catch {
    err => {
      proxy_conn.close()
      raise ProxyConnectionFailed("Failed to read proxy response: \{err}")
    }
  }
  if response.code != 200 {
    proxy_conn.close()
    match response.code {
      407 => raise ProxyAuthenticationRequired
      _ =>
        raise ProxyConnectionFailed(
          "Proxy returned status code \{response.code}: \{response.reason}",
        )
    }
  }
  proxy_conn
}
