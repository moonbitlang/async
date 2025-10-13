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
/// IPv4 address + port number
struct Addr(Bytes) derive(Eq, Compare, Hash)

///|
pub extern "C" fn Addr::new(ip : UInt, port : Int) -> Addr = "moonbitlang_async_make_ip_addr"

///|
extern "C" fn Addr::empty() -> Addr = "moonbitlang_async_make_empty_addr"

///|
#borrow(ip)
extern "C" fn Addr::new_ipv6(ip : FixedArray[Byte], port : Int) -> Addr = "moonbitlang_async_make_ipv6_addr"

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
extern "C" fn ipv6_addrlen() -> Int = "moonbitlang_async_ipv6_addrlen"

///|
#borrow(addr, buf)
extern "C" fn ipv6_name_str(addr : Addr, buf : FixedArray[Byte]) -> Int = "moonbitlang_async_ipv6_name_str"

///|
let _IP_V6_ADDRLEN : Int = ipv6_addrlen()

///|
pub impl Show for Addr with output(self, logger) {
  if self.is_ipv6() {
    // IPv6 address format
    let buf = FixedArray::make(_IP_V6_ADDRLEN, b'0')
    let len = ipv6_name_str(self, buf)
    if len < 0 || len >= _IP_V6_ADDRLEN {
      logger..write_string("[Invalid IPv6 address]")
    } else {
      let addr_str = @encoding/utf8.decode_lossy(
        buf.unsafe_reinterpret_as_bytes()[0:len],
      )
      logger
      ..write_char('[')
      ..write_string(addr_str)
      ..write_char(']')
      ..write_char(':')
      ..write_object(self.port())
    }
  } else {
    // IPv4 address format
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
}

///|
pub suberror InvalidAddr derive(Show)

///|
/// Parse a string into IPv4 or IPv6 address, format should be `ip:port` for IPv4 or `[ip]:port` for IPv6
// TODO: faster implementation
pub fn Addr::parse(src : String) -> Addr raise InvalidAddr {
  if src.has_prefix("[") {
    let (ip_bytes, port, _, _) = try_parse_ipv6(src)
    let ip_bytes = ip_bytes.map(x => x.to_byte())
    Addr::new_ipv6(ip_bytes, port)
  } else {
    // IPv4 format: ip:port
    let (ip, port) = try_parse_ipv4(src) catch { _ => raise InvalidAddr }
    guard 0 <= port && port < 65536 else { raise InvalidAddr }
    Addr::new(ip, port)
  }
}

///|
typealias @event_loop.(AddrInfo, AddrInfoRef)

///|
extern "C" fn AddrInfo::is_null(self : AddrInfo) -> Bool = "moonbitlang_async_addrinfo_is_null"

///|
/// Convert AddrInfo to Addr(support both IPv4 and IPv6)
extern "C" fn AddrInfo::to_addr(self : AddrInfo, port : Int) -> Addr = "moonbitlang_async_addrinfo_to_addr"

///|
extern "C" fn AddrInfo::next(self : AddrInfo) -> AddrInfo = "moonbitlang_async_addrinfo_get_next"

///|
extern "C" fn AddrInfo::free(self : AddrInfo) = "freeaddrinfo"

///|
pub suberror ResolveHostnameError Int derive(Show)

///|
/// Resolve a IPv4 or IPv6 address by hostname.
///
/// An IPv4 address will be returned only if
/// the system has at least one IPv4 address configured.
/// Similarly an IPv6 address will be returned only if
/// the system has at least one IPv6 address configured.
///
/// When both IPv4 and IPv6 is available,
/// currently `Addr::resolve` favors IPv4 address.
pub async fn Addr::resolve(host : String, port~ : Int) -> Addr {
  // TODO: Add option to prefer ipv6 or ipv4
  let host = @encoding/utf8.encode(host)
  let ai_ref = AddrInfoRef::new()
  let ret = @event_loop.perform_job(
    GetAddrInfo(host~, out=ai_ref),
    context="@socket.Addr::resolve_all()",
  )
  if ret != 0 {
    raise ResolveHostnameError(ret)
  }
  let ai_root = ai_ref.get_and_clear()
  defer ai_root.free()
  let first_addr = ai_root.to_addr(port)
  if first_addr.is_ipv6() {
    // if first address is IPv6, try to search for an IPv4 address
    for ai = ai_root.next(); not(ai.is_null()); ai = ai.next() {
      let addr = ai.to_addr(port)
      if not(addr.is_ipv6()) {
        return addr
      }
    }
  }
  first_addr
}
