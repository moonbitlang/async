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
type Ipv4Addr Bytes

///|
type Ipv6Addr Bytes

///|
type IpAddr Bytes

///|
pub(all) enum SocketAddr {
  V4(Ipv4Addr) // IPv4 address and port
  V6(Ipv6Addr) // IPv6 address and port
} derive(Show)

///|
#deprecated("Use @socket.SocketAddr instead")
pub typealias SocketAddr as Addr

///|
pub(open) trait ToSocketAddrs {
  to_socket_addr(self : Self) -> Iter[SocketAddr] raise InvalidAddr
}

///|
pub fn SocketAddr::to_ipaddr(self : SocketAddr) -> IpAddr {
  match self {
    SocketAddr::V4(addr) => addr.to_ipaddr()
    SocketAddr::V6(addr) => addr.to_ipaddr()
  }
}

///|
pub fn SocketAddr::is_ipv4(self : SocketAddr) -> Bool {
  match self {
    SocketAddr::V4(_) => true
    SocketAddr::V6(_) => false
  }
}

///|
pub fn SocketAddr::is_ipv6(self : SocketAddr) -> Bool {
  match self {
    SocketAddr::V4(_) => false
    SocketAddr::V6(_) => true
  }
}

///|
pub extern "C" fn Ipv4Addr::new(ip : UInt, port : Int) -> Ipv4Addr = "moonbitlang_async_make_ip_addr"

///|
#borrow(addr)
pub extern "C" fn Ipv4Addr::ip(addr : Ipv4Addr) -> UInt = "moonbitlang_async_ip_addr_get_ip"

///|
#borrow(addr)
pub extern "C" fn Ipv4Addr::port(addr : Ipv4Addr) -> Int = "moonbitlang_async_ip_addr_get_port"

///|
pub extern "C" fn Ipv6Addr::new(
  ip : FixedArray[Byte],
  port : Int,
  flowinfo : Int,
  scope_id : Int
) -> Ipv6Addr = "moonbitlang_async_make_ipv6_addr"

///|
#borrow(addr, buf)
pub extern "C" fn Ipv6Addr::ip(addr : Ipv6Addr, buf : Bytes) -> Int = "moonbitlang_async_ipv6_addr_get_ip"

///|
#borrow(addr)
pub extern "C" fn Ipv6Addr::port(addr : Ipv6Addr) -> Int = "moonbitlang_async_ipv6_addr_get_port"

///|
pub impl Show for Ipv4Addr with output(self, logger) {
  let ip = self.ip()
  let port = self.port()
  logger
  ..write_object(ip >> 24)
  ..write_char('.')
  ..write_object((ip >> 16) & 255)
  ..write_char('.')
  ..write_object((ip >> 8) & 255)
  ..write_char('.')
  ..write_object(ip & 255)
  ..write_char(':')
  ..write_object(port)
}

///|
pub impl Show for Ipv6Addr with output(self, logger) {
  let ip_buf = Bytes::make(_IP_V6_ADDRLEN, Byte::default())
  let len = self.ip(ip_buf)
  let ip_str = utf8_bytes_to_mbt_string(ip_buf[0:len].to_bytes())
  logger.write_char('[')
  logger.write_string(ip_str)
  logger.write_char(']')
  logger.write_char(':')
  logger.write_object(self.port())
}

///|
pub suberror InvalidAddr derive(Show)

///|
/// Parse a string into IPv4 address, format should be `ip:port` (no space)
// TODO: faster implementation
pub fn Ipv4Addr::parse(src : String) -> Ipv4Addr raise InvalidAddr {
  let (ip, port) = try_parse_ipv4(src) catch { _ => raise InvalidAddr }
  Ipv4Addr::new(ip, port)
}

///|
pub fn Ipv6Addr::parse(src : String) -> Ipv6Addr raise InvalidAddr {
  let (ip_bytes, port, flowinfo, scope_id) = try_parse_ipv6(src)
  let ip_bytes = ip_bytes.map(x => x.to_byte())
  Ipv6Addr::new(ip_bytes, port, flowinfo, scope_id)
}

///|
pub fn SocketAddr::parse(src : String) -> SocketAddr raise InvalidAddr {
  parse_address(src) catch {
    _ => raise InvalidAddr
  }
}

///|
fn parse_address(src : String) -> SocketAddr raise {
  // Try to parse IPv6 format [addr]:port
  if src.has_prefix("[") {
    let addr = Ipv6Addr::parse(src)
    return SocketAddr::V6(addr)
  }
  let addr = Ipv4Addr::parse(src)
  SocketAddr::V4(addr)
}
