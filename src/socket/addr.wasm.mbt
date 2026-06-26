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
priv enum AddrFamily {
  IPv4 = 4
  IPv6 = 6
}

///|
struct Addr(Bytes) derive(Eq, Compare, Hash)

///|
#unsafe_skip_stub_check
fn get_ipv4_addr_size() -> Int = "moonbitlang/async" "socket/ipv4_addr_size"

///|
let ipv4_addr_size : Int = get_ipv4_addr_size()

///|
#unsafe_skip_stub_check
fn get_ipv6_addr_size() -> Int = "moonbitlang/async" "socket/ipv6_addr_size"

///|
let ipv6_addr_size : Int = get_ipv6_addr_size()

///|
#unsafe_skip_stub_check
#borrow(addr)
fn init_ip_addr(addr : Bytes, ip : UInt, port : Int) -> Unit = "moonbitlang/async" "socket/init_ip_addr"

///|
pub fn Addr::new(ip : UInt, port : Int) -> Addr {
  let addr = Bytes::make(ipv4_addr_size, 0)
  init_ip_addr(addr, ip, port)
  Addr(addr)
}

///|
#unsafe_skip_stub_check
#borrow(addr, ip)
fn init_ipv6_addr(
  addr : Bytes,
  ip : FixedArray[Byte],
  port : Int,
  scope_id~ : UInt,
) -> Unit = "moonbitlang/async" "socket/init_ipv6_addr"

///|
fn Addr::new_ipv6(ip : FixedArray[Byte], port : Int, scope_id~ : UInt) -> Addr {
  let addr = Bytes::make(ipv6_addr_size, 0)
  init_ipv6_addr(addr, ip, port, scope_id~)
  Addr(addr)
}

///|
let empty_ipv6_bytes : FixedArray[Byte] = FixedArray::make(16, 0)

///|
let ipv4_any : Ref[Addr?] = Ref(None)

///|
let ipv6_any : Ref[Addr?] = Ref(None)

///|
fn Addr::empty(family : AddrFamily) -> Addr {
  match family {
    IPv4 => {
      let addr = Bytes::make(ipv4_addr_size, 0)
      init_ip_addr(addr, 0, 0)
      Addr(addr)
    }
    IPv6 => {
      let addr = Bytes::make(ipv6_addr_size, 0)
      init_ipv6_addr(addr, empty_ipv6_bytes, 0, scope_id=0)
      Addr(addr)
    }
  }
}

///|
fn Addr::any(family : AddrFamily) -> Addr {
  // Defer construction because borrowed host imports cannot safely initialize Addr globals in Wasm.
  let cache = match family {
    IPv4 => ipv4_any
    IPv6 => ipv6_any
  }
  match cache.val {
    Some(addr) => addr
    None => {
      let addr = Addr::empty(family)
      cache.val = Some(addr)
      addr
    }
  }
}

///|
#unsafe_skip_stub_check
#borrow(addr)
fn ip_addr_get_ip(addr : Addr, addr_len? : Int = addr.0.length()) -> UInt = "moonbitlang/async" "socket/ip_addr_get_ip"

///|
pub fn Addr::ip(addr : Addr) -> UInt {
  ip_addr_get_ip(addr)
}

///|
#unsafe_skip_stub_check
#borrow(addr)
fn ip_addr_get_port(addr : Addr, addr_len? : Int = addr.0.length()) -> Int = "moonbitlang/async" "socket/ip_addr_get_port"

///|
pub fn Addr::port(addr : Addr) -> Int {
  ip_addr_get_port(addr)
}

///|
#unsafe_skip_stub_check
#borrow(addr)
fn addr_is_ipv6(addr : Addr, addr_len? : Int = addr.0.length()) -> Bool = "moonbitlang/async" "socket/addr_is_ipv6"

///|
pub fn Addr::is_ipv6(addr : Addr) -> Bool {
  addr_is_ipv6(addr)
}

///|
#unsafe_skip_stub_check
#borrow(addr)
fn addr_is_multicast(addr : Addr, addr_len? : Int = addr.0.length()) -> Bool = "moonbitlang/async" "socket/addr_is_multicast"

///|
pub fn Addr::is_multicast(addr : Addr) -> Bool {
  addr_is_multicast(addr)
}

///|
fn Addr::family(self : Addr) -> AddrFamily {
  if self.is_ipv6() {
    IPv6
  } else {
    IPv4
  }
}

///|
#unsafe_skip_stub_check
#borrow(addr, out)
fn Addr::copy_ipv6_bytes(
  addr : Addr,
  out : FixedArray[Byte],
  addr_len? : Int = addr.0.length(),
  len? : Int = out.length(),
) -> Unit = "moonbitlang/async" "socket/addr_copy_ipv6_bytes"

///|
#unsafe_skip_stub_check
#borrow(addr)
fn Addr::scope_id(addr : Addr, addr_len? : Int = addr.0.length()) -> UInt = "moonbitlang/async" "socket/addr_get_ipv6_scope_id"

///|
#unsafe_skip_stub_check
#borrow(addr)
fn Addr::is_ipv6_wildcard(
  addr : Addr,
  addr_len? : Int = addr.0.length(),
) -> Bool = "moonbitlang/async" "socket/addr_is_ipv6_wildcard"

///|
pub impl Show for Addr with fn output(self, logger) {
  if self.is_ipv6() {
    logger <+ "["
    let ip : FixedArray[Byte] = FixedArray::make(16, 0)
    self.copy_ipv6_bytes(ip)
    write_ipv6_str(ip, logger)
    let scope_id = self.scope_id()
    if scope_id > 0 {
      let interface = if_indextoname(scope_id, context="") catch {
        _ => scope_id.to_string()
      }
      logger <+ "%\{interface}"
    }
    logger <+ "]:\{self.port()}"
  } else {
    let ip = self.ip()
    let port = self.port()
    logger <+
      "\{ip >> 24}.\{(ip >> 16) & 255}.\{(ip >> 8) & 255}.\{ip & 255}:\{port}"
  }
}

///|
pub suberror InvalidAddr derive(Debug, ToJson)

///|
pub fn Addr::parse(src : String) -> Addr raise {
  if src.has_prefix("[") {
    let (ip_bytes, port, interface) = try_parse_ipv6(src)
    let scope_id = if interface is Some(interface) {
      parse_ipv6_zone_suffix(interface, context="@socket.Addr::parse()")
    } else {
      0
    }
    Addr::new_ipv6(ip_bytes, port, scope_id~)
  } else {
    let (ip, port) = try_parse_ipv4(src) catch { _ => raise InvalidAddr }
    guard 0 <= port && port < 65536 else { raise InvalidAddr }
    Addr::new(ip, port)
  }
}

///|
using @event_loop {type AddrInfo}

///|
#unsafe_skip_stub_check
fn AddrInfo::is_null(self : AddrInfo) -> Bool = "moonbitlang/async" "socket/addrinfo_is_null"

///|
#unsafe_skip_stub_check
fn AddrInfo::addr_size(self : AddrInfo) -> Int = "moonbitlang/async" "socket/addrinfo_addr_size"

///|
#unsafe_skip_stub_check
#borrow(out)
fn AddrInfo::fill_addr(
  self : AddrInfo,
  out : Bytes,
  port : Int,
  out_len? : Int = out.length(),
) -> Unit = "moonbitlang/async" "socket/addrinfo_fill_addr"

///|
fn AddrInfo::to_addr(self : AddrInfo, port : Int) -> Addr {
  let addr = Bytes::make(self.addr_size(), 0)
  self.fill_addr(addr, port)
  Addr(addr)
}

///|
#unsafe_skip_stub_check
fn AddrInfo::next(self : AddrInfo) -> AddrInfo = "moonbitlang/async" "socket/addrinfo_get_next"

///|
#unsafe_skip_stub_check
fn AddrInfo::free(self : AddrInfo) -> Unit = "moonbitlang/async" "socket/addrinfo_free"

///|
pub(all) enum IpProtocolPreference {
  OnlyV4
  OnlyV6
  FavorV4
  FavorV6
  NoPreference
} derive(Debug)

///|
pub suberror ResolveHostnameError {
  ResolveHostnameError(String)
} derive(Debug, ToJson)

///|
pub async fn Addr::resolve(
  host : String,
  port~ : Int,
  protocol? : IpProtocolPreference = NoPreference,
) -> Addr {
  let context = "@socket.Addr::resolve()"
  let ai_root = match @event_loop.getaddrinfo(host, context~) {
    Ok(ai_root) => ai_root
    Err(msg) => raise ResolveHostnameError(msg)
  }
  defer ai_root.free()
  let first_addr = ai_root.to_addr(port)
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

///|
fn try_parse_ipv6(
  input : String,
) -> (FixedArray[Byte], Int, String?) raise InvalidAddr {
  guard input.has_prefix("[") else { raise InvalidAddr }
  guard input.rev_find("]") is Some(bracket_end) else { raise InvalidAddr }
  let remaining = input[bracket_end + 1:]
  guard remaining.has_prefix(":") else { raise InvalidAddr }
  let ip_str = input[1:bracket_end]
  let port_str = remaining[1:]
  let (ip_str, interface) = if ip_str.find("%") is Some(ip_end) {
    let interface = ip_str[ip_end + 1:]
    guard interface.length() > 0 else { raise InvalidAddr }
    (ip_str[:ip_end], Some(interface.to_owned()))
  } else {
    (ip_str, None)
  }
  let ip_bytes = parse_ipv6_to_bytes(ip_str)
  let port = parse_port(port_str)
  (ip_bytes, port, interface)
}

///|
fn parse_ipv6_to_bytes(
  ip_str : StringView,
) -> FixedArray[Byte] raise InvalidAddr {
  if ip_str == "::" {
    return FixedArray::make(16, 0)
  }
  match ip_str.split("::").collect() {
    [ip_str] => parse_full_ipv6_to_bytes(ip_str)
    [left_part, right_part] =>
      parse_compressed_ipv6_to_bytes(left_part, right_part)
    _ => raise InvalidAddr
  }
}

///|
fn parse_compressed_ipv6_to_bytes(
  left_part : StringView,
  right_part : StringView,
) -> FixedArray[Byte] raise InvalidAddr {
  let left_groups = if left_part.is_empty() {
    []
  } else {
    left_part.split(":").collect()
  }
  let right_groups = if right_part.is_empty() {
    []
  } else {
    right_part.split(":").collect()
  }
  let ipv4_bytes = if !right_groups.is_empty() &&
    right_groups[right_groups.length() - 1].contains(".") {
    Some(parse_ipv4_to_bytes(right_groups.unsafe_pop()))
  } else {
    None
  }
  let ipv4_group_count = if ipv4_bytes is None { 0 } else { 2 }
  let total_explicit_groups = left_groups.length() +
    right_groups.length() +
    ipv4_group_count
  guard total_explicit_groups < 8 else { raise InvalidAddr }
  let compression_groups = 8 - total_explicit_groups
  let result : FixedArray[Byte] = FixedArray::make(16, 0)
  let mut byte_index = 0
  for group_str in left_groups {
    let group_value = parse_ipv6_group(group_str)
    result[byte_index] = ((group_value >> 8) & 0xFF).to_byte()
    result[byte_index + 1] = (group_value & 0xFF).to_byte()
    byte_index += 2
  }
  for _ in 0..<compression_groups {
    result[byte_index] = 0
    result[byte_index + 1] = 0
    byte_index += 2
  }
  for group_str in right_groups {
    let group_value = parse_ipv6_group(group_str)
    result[byte_index] = ((group_value >> 8) & 0xFF).to_byte()
    result[byte_index + 1] = (group_value & 0xFF).to_byte()
    byte_index += 2
  }
  if ipv4_bytes is Some((a, b, c, d)) {
    result[byte_index + 0] = a.to_byte()
    result[byte_index + 1] = b.to_byte()
    result[byte_index + 2] = c.to_byte()
    result[byte_index + 3] = d.to_byte()
  }
  result
}

///|
fn parse_full_ipv6_to_bytes(
  ip_str : StringView,
) -> FixedArray[Byte] raise InvalidAddr {
  let parts = ip_str.split(":").collect()
  let result : FixedArray[Byte] = FixedArray::make(16, 0)
  let ipv4_bytes = if parts[parts.length() - 1].contains(".") {
    guard parts.length() == 7 else { raise InvalidAddr }
    Some(parse_ipv4_to_bytes(parts.unsafe_pop()))
  } else {
    guard parts.length() == 8 else { raise InvalidAddr }
    None
  }
  let mut byte_index = 0
  for part in parts {
    let group_value = parse_ipv6_group(part)
    result[byte_index] = ((group_value >> 8) & 0xFF).to_byte()
    result[byte_index + 1] = (group_value & 0xFF).to_byte()
    byte_index += 2
  }
  if ipv4_bytes is Some((a, b, c, d)) {
    result[byte_index + 0] = a.to_byte()
    result[byte_index + 1] = b.to_byte()
    result[byte_index + 2] = c.to_byte()
    result[byte_index + 3] = d.to_byte()
  }
  result
}

///|
fn parse_ipv6_group(group : StringView) -> UInt raise InvalidAddr {
  guard !group.is_empty() && group.length() <= 4 else { raise InvalidAddr }
  @string.parse_uint(group, base=16) catch {
    _ => raise InvalidAddr
  }
}

///|
fn parse_ipv6_zone_suffix(zone : StringView, context~ : String) -> UInt raise {
  try @string.parse_uint(zone) catch {
    _ => if_nametoindex(zone, context~)
  } noraise {
    index => index
  }
}

///|
fn parse_ipv4_to_bytes(
  ip_str : StringView,
) -> (UInt, UInt, UInt, UInt) raise InvalidAddr {
  let parts = ip_str.split(".").collect()
  guard parts.length() == 4 else { raise InvalidAddr }
  fn parse_octal(x : StringView) raise InvalidAddr {
    let value = @string.parse_uint(x) catch { _ => raise InvalidAddr }
    guard value < 256 else { raise InvalidAddr }
    value
  }
  (
    parse_octal(parts[0]),
    parse_octal(parts[1]),
    parse_octal(parts[2]),
    parse_octal(parts[3]),
  )
}

///|
fn try_parse_ipv4(input : String) -> (UInt, Int) raise InvalidAddr {
  guard input.rev_find(":") is Some(last_colon) else { raise InvalidAddr }
  let ip_str = input[:last_colon]
  let port_str = input[last_colon + 1:]
  let port = parse_port(port_str)
  let (a, b, c, d) = parse_ipv4_to_bytes(ip_str.view())
  let ip = (a << 24) | (b << 16) | (c << 8) | d
  (ip, port)
}

///|
fn parse_port(port_str : StringView) -> Int raise InvalidAddr {
  guard !port_str.is_empty() else { raise InvalidAddr }
  let port = @string.parse_int(port_str) catch { _ => raise InvalidAddr }
  guard 0 <= port && port < 65536 else { raise InvalidAddr }
  port
}

///|
fn write_ipv6_str(addr : FixedArray[Byte], logger : &Logger) -> Unit {
  let mut longest_zero_group = None
  fn add_zero_group(start, end) {
    if end > start {
      match longest_zero_group {
        Some((start0, end0)) if end0 - start0 >= end - start => ()
        _ => longest_zero_group = Some((start, end))
      }
    }
  }
  for i = 0, zero_group_start = 0; i < 8; i = i + 1 {
    if addr[i * 2] == 0 && addr[i * 2 + 1] == 0 {
      continue
    } else {
      add_zero_group(zero_group_start, i)
      continue i + 1, i + 1
    }
  } nobreak {
    add_zero_group(zero_group_start, i)
  }
  let is_v4_mapped = match longest_zero_group {
    Some((0, 6)) => true
    Some((0, 5)) => addr[10] is 0xff && addr[11] is 0xff
    _ => false
  }
  let hex_format_end = if is_v4_mapped { 6 } else { 8 }
  for i = 0; i < hex_format_end; i = i + 1 {
    match longest_zero_group {
      Some((start, end)) if i == start => {
        if i == 0 {
          logger <+ "::"
        } else {
          logger <+ ":"
        }
        continue end
      }
      _ => ()
    }
    let value = (addr[i * 2].to_int() << 8) | addr[i * 2 + 1].to_int()
    logger <+ "\{value.to_string(radix=16)}"
    if i < 7 {
      logger <+ ":"
    }
  }
  if is_v4_mapped {
    logger <+
      "\{addr[12].to_int()}.\{addr[13].to_int()}.\{addr[14].to_int()}.\{addr[15].to_int()}"
  }
}
