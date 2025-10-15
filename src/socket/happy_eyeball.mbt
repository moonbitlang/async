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
/// Connect to a remote host using the happy eyeball algorithm.
/// Preference on IPv4 v.s. IPv6 can be configured via `protocol`:
///
/// - if `protocol` is `No_Preference` (the default behavior),
///   the first successful connection will be returned, regardless of the protocol.
/// - if `protocol` is `Favor_V4`,
///   an IPv6 connection will only be returned if no IPv4 address is available
/// - if `protocol` is `Only_V4`,
///   `connect_to_host` will fail if no IPv4 address is available
/// - if `protocol` is `Favor_V6`,
///   an IPv6 connection will only be returned if no IPv4 address is available
/// - if `protocol` is `Only_V6`,
///   `connect_to_host` will fail if no IPv4 address is available
pub async fn Tcp::connect_to_host(
  host : String,
  port~ : Int,
  protocol? : IPProtocolPreference = No_Preference,
) -> Tcp {
  let host = @encoding/utf8.encode(host)
  let ai_ref = AddrInfoRef::new()
  let ret = @event_loop.perform_job(
    GetAddrInfo(host~, out=ai_ref),
    context="@socket.Tcp::connect_to_host()",
  )
  if ret > 0 {
    raise ResolveHostnameError::from_error_code(ret)
  }
  let mut result = None
  let mut conn_err = None
  let ai = ai_ref.get_and_clear()
  defer ai.free()
  async fn connect_with_protocol(protocol : IPProtocolPreference) {
    @async.with_task_group(fn(group) {
      for ai = ai; not(ai.is_null()); ai = ai.next() {
        let addr = ai.to_addr(port)
        match (protocol, addr.is_ipv6()) {
          (Only_V4 | Favor_V4, true) => continue
          (Only_V6 | Favor_V6, false) => continue
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
    No_Preference | Only_V4 | Only_V6 => connect_with_protocol(protocol)
    Favor_V4 => {
      connect_with_protocol(Only_V4)
      if result is None {
        connect_with_protocol(Only_V6)
      }
    }
    Favor_V6 => {
      connect_with_protocol(Only_V6)
      if result is None {
        connect_with_protocol(Only_V4)
      }
    }
  }
  match result {
    Some(conn) => conn
    None =>
      match (conn_err, protocol) {
        (Some(err), _) => raise err
        (None, Only_V4) =>
          raise ResolveHostnameError("No available IPv4 address")
        (None, Only_V6) =>
          raise ResolveHostnameError("No available IPv6 address")
        (None, _) => panic()
      }
  }
}
