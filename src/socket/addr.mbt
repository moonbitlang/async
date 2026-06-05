/// Copyright 2025 International Digital Economy Academy
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
priv enum AddrFamily {
  IPv4 = 4
  IPv6 = 6
}

///|
#warnings("-unused_constructor")
struct Addr(Bytes) derive(Eq, Compare, Hash)

///|
extern "C" fn ipv4_addr_size() -> Int = "moonbitlang_async_ipv4_addr_size"

///|
extern "C" fn ipv6_addr_size() -> Int = "moonbitlang_async_ipv6_addr_size"

///|
#borrow(addr)
extern "C" fn init_ip_addr(addr : Bytes, ip : UInt, port : Int) = "moonbitlang_async_init_ip_addr"

///|
pub fn Addr::new(ip : UInt, port : Int) -> Addr {
  let addr = Bytes::make(ipv4_addr_size(), 0)
  init_ip_addr(addr, ip, port)
  Addr(addr)
}

///|
#borrow(addr)
extern "C" fn init_empty_addr(addr : Bytes, family : AddrFamily) = "moonbitlang_async_init_empty_addr"

///|
fn Addr::empty(family : AddrFamily) -> Addr {
  let size = match family {
    IPv4 => ipv4_addr_size()
    IPv6 => ipv6_addr_size()
  }
  let addr = Bytes::make(size, 0)
  init_empty_addr(addr, family)
  Addr(addr)
}

///|
#borrow(addr, ip)
extern "C" fn init_ipv6_addr(
  addr : Bytes,
  ip : FixedArray[Byte],
  port : Int,
  scope_id~ : UInt,
) = "moonbitlang_async_init_ipv6_addr"

///|
fn Addr::new_ipv6(ip : FixedArray[Byte], port : Int, scope_id~ : UInt) -> Addr {
  let addr = Bytes::make(ipv6_addr_size(), 0)
  init_ipv6_addr(addr, ip, port, scope_id~)
  Addr(addr)
}

///|
#borrow(addr)
pub extern "C" fn Addr::ip(addr : Addr) -> UInt = "moonbitlang_async_ip_addr_get_ip"

///|
#borrow(addr)
pub extern "C" fn Addr::port(addr : Addr) -> Int = "moonbitlang_async_ip_addr_get_port"

///|
#borrow(addr)
pub extern "C" fn Addr::is_ipv6(addr : Addr) -> Bool = "moonbitlang_async_addr_is_ipv6"

///|
#borrow(addr)
pub extern "C" fn Addr::is_multicast(addr : Addr) -> Bool = "moonbitlang_async_addr_is_multicast"

///|
fn Addr::family(self : Addr) -> AddrFamily {
  if self.is_ipv6() {
    IPv6
  } else {
    IPv4
  }
}

///|
let ipv4_any : Addr = Addr::new(0, 0)

///|
let ipv6_any : Addr = Addr::new_ipv6(FixedArray::make(16, 0), 0, scope_id=0)

///|
#borrow(addr)
extern "C" fn Addr::get_ipv6_bytes(addr : Addr) -> @c_buffer.Buffer = "moonbitlang_async_addr_get_ipv6_bytes"

///|
#borrow(addr)
extern "C" fn Addr::scope_id(addr : Addr) -> UInt = "moonbitlang_async_addr_get_ipv6_scope_id"

///|
#borrow(addr)
extern "C" fn Addr::is_ipv6_wildcard(addr : Addr) -> Bool = "moonbitlang_async_addr_is_ipv6_wildcard"

///|
pub impl Show for Addr with output(self, logger) {
  if self.is_ipv6() {
    // IPv6 address format
    logger <+ "["
    write_ipv6_str(self.get_ipv6_bytes(), logger)
    let scope_id = self.scope_id()
    if scope_id > 0 {
      let interface = if_indextoname(scope_id, context="") catch {
        _ => scope_id.to_string()
      }
      logger <+ "%\{interface}"
    }
    logger <+ "]:\{self.port()}"
  } else {
    // IPv4 address format
    let ip = self.ip()
    let port = self.port()
    logger
      <+
      "\{ip >> 24}.\{(ip >> 16) & 255}.\{(ip >> 8) & 255}.\{ip & 255}:\{port}"
  }
}

///|
pub suberror InvalidAddr derive(Debug, ToJson)

///|
/// Parse a string into IPv4 or IPv6 address, format should be `ip:port` for IPv4 or `[ip]:port` for IPv6
// TODO: faster implementation
pub fn Addr::parse(src : String) -> Addr raise {
  if src.has_prefix("[") {
    let (ip_bytes, port, interface) = try_parse_ipv6(src)
    let scope_id = if interface is Some(interface) {
      parse_ipv6_zone_suffix(interface, context="socket.Addr::parse()")
    } else {
      0
    }
    Addr::new_ipv6(ip_bytes, port, scope_id~)
  } else {
    // IPv4 format: ip:port
    let (ip, port) = try_parse_ipv4(src) catch { _ => raise InvalidAddr }
    guard 0 <= port && port < 65536 else { raise InvalidAddr }
    Addr::new(ip, port)
  }
}

///|
using @event_loop {type AddrInfo}

///|
extern "C" fn AddrInfo::is_null(self : AddrInfo) -> Bool = "moonbitlang_async_addrinfo_is_null"

///|
/// Convert AddrInfo to Addr(support both IPv4 and IPv6)
extern "C" fn AddrInfo::addr_size(self : AddrInfo) -> Int = "moonbitlang_async_addrinfo_addr_size"

///|
#borrow(out)
extern "C" fn AddrInfo::fill_addr(
  self : AddrInfo,
  out : Bytes,
  port : Int,
) -> Bool = "moonbitlang_async_addrinfo_fill_addr"

///|
fn AddrInfo::to_addr(self : AddrInfo, port : Int) -> Addr {
  let size = self.addr_size()
  guard size > 0 else {
    abort("unsupported address family returned from getaddrinfo")
  }
  let addr = Bytes::make(size, 0)
  guard self.fill_addr(addr, port) else {
    abort("failed to copy address returned from getaddrinfo")
  }
  Addr(addr)
}

///|
extern "C" fn AddrInfo::next(self : AddrInfo) -> AddrInfo = "moonbitlang_async_addrinfo_get_next"

///|
#cfg(not(platform="windows"))
extern "C" fn AddrInfo::free(self : AddrInfo) = "freeaddrinfo"

///|
#cfg(platform="windows")
extern "C" fn AddrInfo::free(self : AddrInfo) = "moonbitlang_async_freeaddrinfo"

///|
/// Error message from failure in resolving a network hostname.
/// The content of the error message is platfrom-dependent,
/// so users should never depend on it.
pub suberror ResolveHostnameError {
  ResolveHostnameError(String)
} derive(Debug, ToJson)

///|
pub(all) enum IpProtocolPreference {
  OnlyV4
  OnlyV6
  FavorV4
  FavorV6
  NoPreference
} derive(Debug)

///|
/// Resolve a IPv4 or IPv6 address by hostname.
///
/// By default, `Addr::resolve` return the first available address.
/// Preference on IPv4 v.s. IPv6 can be configured via `protocol`.
/// See `IPProtocolPreference` for available options.
pub async fn Addr::resolve(
  host : String,
  port~ : Int,
  protocol? : IpProtocolPreference = NoPreference,
) -> Addr {
  // TODO: Add option to prefer ipv6 or ipv4
  let context = "@socket.Addr::resolve()"
  let ai_root = match @event_loop.getaddrinfo(host, context~) {
    Ok(ai_root) => ai_root
    Err(msg) => raise ResolveHostnameError(msg)
  }
  defer ai_root.free()
  let first_addr = ai_root.to_addr(port)

  // search for address with preferred protocol
  match protocol {
    FavorV4 | OnlyV4 => {
      if !first_addr.is_ipv6() {
        return first_addr
      }
      for ai = ai_root.next(); !ai.is_null(); ai = ai.next() {
        let addr = ai.to_addr(port)
        if !addr.is_ipv6() {
          return addr
        }
      }
      if protocol is OnlyV4 {
        raise ResolveHostnameError("No available IPv4 address")
      } else {
        first_addr
      }
    }
    FavorV6 | OnlyV6 => {
      if first_addr.is_ipv6() {
        return first_addr
      }
      for ai = ai_root.next(); !ai.is_null(); ai = ai.next() {
        let addr = ai.to_addr(port)
        if addr.is_ipv6() {
          return addr
        }
      }
      if protocol is OnlyV6 {
        raise ResolveHostnameError("No available IPv6 address")
      } else {
        first_addr
      }
    }
    NoPreference => first_addr
  }
}
