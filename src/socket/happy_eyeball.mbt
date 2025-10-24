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

/// Connect to a remote host using the Happy Eyeballs algorithm (RFC 6555).
///
/// This algorithm attempts to connect to both IPv4 and IPv6 addresses
/// simultaneously to improve connection reliability and speed.
///
/// # Parameters
/// - `host`: The hostname to connect to
/// - `port`: The port number
/// - `protocol`: IP protocol preference (default: `NoPreference`)
///
/// # Protocol Preference Behavior
/// - `NoPreference`: Return the first successful connection
/// - `FavorV4`: Prefer IPv4, only use IPv6 if IPv4 unavailable
/// - `OnlyV4`: Only attempt IPv4 connections
/// - `FavorV6`: Prefer IPv6, only use IPv4 if IPv6 unavailable
/// - `OnlyV6`: Only attempt IPv6 connections
///
/// # Returns
/// A connected TCP socket
///
/// # Raises
/// `ResolveHostnameError` if hostname resolution fails or no suitable address is found
///
/// # Example
/// ```
/// // Usage: let conn = Tcp::connect_to_host("example.com", port=80)!
/// // Usage: let ipv4_conn = Tcp::connect_to_host("example.com", port=80, protocol=OnlyV4)!
/// ```
pub async fn Tcp::connect_to_host(
  host : String,
  port~ : Int,
  protocol? : IpProtocolPreference = NoPreference,
) -> Tcp {
  let context = "@socket.Tcp::connect_to_host()"
  let ai = match @event_loop.getaddrinfo(host, context~) {
    Ok(ai) => ai
    Err(msg) => raise ResolveHostnameError(msg)
  }
  defer ai.free()
  let mut result = None
  let mut conn_err = None
  async fn connect_with_protocol(protocol : IpProtocolPreference) {
    @async.with_task_group(fn(group) {
      for ai = ai; not(ai.is_null()); ai = ai.next() {
        let addr = ai.to_addr(port)
        match (protocol, addr.is_ipv6()) {
          (OnlyV4 | FavorV4, true) => continue
          (OnlyV6 | FavorV6, false) => continue
          _ => ()
        }
        group.spawn_bg(allow_failure=true, fn() {
          let conn = Tcp::connect(addr) catch {
            err => {
              if conn_err is None {
                conn_err = Some(err)
              }
              raise err
            }
          }
          result = Some(conn)
          group.return_immediately(())
        })
        @async.sleep(250)
      }
    })
  }

  match protocol {
    NoPreference | OnlyV4 | OnlyV6 => connect_with_protocol(protocol)
    FavorV4 => {
      connect_with_protocol(OnlyV4)
      if result is None {
        connect_with_protocol(OnlyV6)
      }
    }
    FavorV6 => {
      connect_with_protocol(OnlyV6)
      if result is None {
        connect_with_protocol(OnlyV4)
      }
    }
  }
  match result {
    Some(conn) => conn
    None =>
      match (conn_err, protocol) {
        (Some(err), _) => raise err
        (None, OnlyV4) =>
          raise ResolveHostnameError("No available IPv4 address")
        (None, OnlyV6) =>
          raise ResolveHostnameError("No available IPv6 address")
        (None, _) => panic()
      }
  }
}
