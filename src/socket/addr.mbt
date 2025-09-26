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
#borrow(addr)
pub extern "C" fn Addr::ip(addr : Addr) -> UInt = "moonbitlang_async_ip_addr_get_ip"

///|
#borrow(addr)
pub extern "C" fn Addr::port(addr : Addr) -> Int = "moonbitlang_async_ip_addr_get_port"

///|
pub impl Show for Addr with output(self, logger) {
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
pub suberror InvalidAddr derive(Show)

///|
/// Parse a string into IPv4 address, format should be `ip:port` (no space)
// TODO: faster implementation
pub fn Addr::parse(src : String) -> Addr raise InvalidAddr {
  guard src.split(":").collect() is [ip, port] else { raise InvalidAddr }
  guard ip.split(".").collect() is [a, b, c, d] else { raise InvalidAddr }
  fn parse_octal(x : StringView) raise InvalidAddr {
    let value = @strconv.parse_uint(x.to_string()) catch {
      _ => raise InvalidAddr
    }
    guard value < 256 else { raise InvalidAddr }
    value
  }

  let ip = (parse_octal(a) << 24) |
    (parse_octal(b) << 16) |
    (parse_octal(c) << 8) |
    parse_octal(d)
  let port = @strconv.parse_int(port.to_string()) catch {
    _ => raise InvalidAddr
  }
  guard 0 <= port && port < 65536 else { raise InvalidAddr }
  Addr::new(ip, port)
}

///|
typealias @event_loop.(AddrInfo, AddrInfoRef)

///|
extern "C" fn AddrInfo::is_null(self : AddrInfo) -> Bool = "moonbitlang_async_addrinfo_is_null"

///|
extern "C" fn AddrInfo::ip(self : AddrInfo) -> UInt = "moonbitlang_async_addrinfo_get_ip"

///|
extern "C" fn AddrInfo::next(self : AddrInfo) -> AddrInfo = "moonbitlang_async_addrinfo_get_next"

///|
extern "C" fn AddrInfo::free(self : AddrInfo) = "freeaddrinfo"

///|
pub suberror ResolveHostnameError Int derive(Show)

///|
/// Resolve a IPv4 address by hostname
pub async fn Addr::resolve(host : String, port~ : Int) -> Addr {
  let host = @encoding/utf8.encode(host)
  let ai_ref = AddrInfoRef::new()
  let ret = @event_loop.perform_job(
    GetAddrInfo(host~, out=ai_ref),
    context="@socket.Addr::resolve()",
  )
  if ret != 0 {
    raise ResolveHostnameError(ret)
  }
  let ai = ai_ref.get_and_clear()
  defer ai.free()
  Addr::new(ai.ip(), port)
}
