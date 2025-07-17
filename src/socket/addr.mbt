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
type Addr Bytes

///|
type Ipv6Addr Bytes

///|
pub extern "C" fn Addr::new(ip : UInt, port : Int) -> Addr = "moonbitlang_async_make_ip_addr"

///|
#borrow(addr)
pub extern "C" fn Addr::ip(addr : Addr) -> UInt = "moonbitlang_async_ip_addr_get_ip"

///|
#borrow(addr)
pub extern "C" fn Addr::port(addr : Addr) -> Int = "moonbitlang_async_ip_addr_get_port"

///|
pub extern "C" fn Ipv6Addr::new(
  ip : FixedArray[Byte],
  port : Int,
  flowinfo : Int,
  scope_id : Int
) -> Ipv6Addr = "moonbitlang_async_make_ipv6_addr"

///|
#borrow(addr)
pub extern "C" fn Ipv6Addr::ip(addr : Ipv6Addr, buf : Bytes) -> Int = "moonbitlang_async_ipv6_addr_get_ip"

///|
#borrow(addr)
pub extern "C" fn Ipv6Addr::port(addr : Ipv6Addr) -> Int = "moonbitlang_async_ipv6_addr_get_port"

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
pub impl Show for Ipv6Addr with output(self, logger) {
  let ip_buf = Bytes::make(47, Byte::default())
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
pub fn Addr::parse(src : String) -> Addr raise InvalidAddr {
  let (ip, port) = try_parse_ipv4(src) catch { _ => raise InvalidAddr }
  Addr::new(ip, port)
}

///|
pub fn Ipv6Addr::parse(src : String) -> Ipv6Addr raise InvalidAddr {
  let (ip_bytes, port, flowinfo, scope_id) = try_parse_ipv6(src)
  let ip_bytes = ip_bytes.map(x => x.to_byte())
  Ipv6Addr::new(ip_bytes, port, flowinfo, scope_id)
}
