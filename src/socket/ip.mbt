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

///|
extern "C" fn _af_inet_ffi() -> Int = "moonbitlang_AF_INET"

///|
extern "C" fn _af_inet6_ffi() -> Int = "moonbitlang_AF_INET6"

///|
extern "C" fn _af_unix_ffi() -> Int = "moonbitlang_AF_UNIX"

///|
extern "C" fn _af_unspec_ffi() -> Int = "moonbitlang_AF_UNSPEC"

///|
extern "C" fn _sock_stream_ffi() -> Int = "moonbitlang_SOCK_STREAM"

///|
extern "C" fn _sock_dgram_ffi() -> Int = "moonbitlang_SOCK_DGRAM"

///|
extern "C" fn _sock_raw_ffi() -> Int = "moonbitlang_SOCK_RAW"

///|
extern "C" fn _ipproto_tcp_ffi() -> Int = "moonbitlang_IPPROTO_TCP"

///|
extern "C" fn _ipproto_udp_ffi() -> Int = "moonbitlang_IPPROTO_UDP"

///|
extern "C" fn _ipproto_icmp_ffi() -> Int = "moonbitlang_IPPROTO_ICMP"

///|
extern "C" fn _ipproto_icmpv6_ffi() -> Int = "moonbitlang_IPPROTO_ICMPV6"

///|
let _AF_INET : Int = _af_inet_ffi()

///|
let _AF_INET6 : Int = _af_inet6_ffi()

///|
let _AF_UNIX : Int = _af_unix_ffi()

///|
let _AF_UNSPEC : Int = _af_unspec_ffi()

///|
let _SOCK_STREAM : Int = _sock_stream_ffi()

///|
let _SOCK_DGRAM : Int = _sock_dgram_ffi()

///|
let _SOCK_RAW : Int = _sock_raw_ffi()

///|
let _IPPROTO_TCP : Int = _ipproto_tcp_ffi()

///|
let _IPPROTO_UDP : Int = _ipproto_udp_ffi()

///|
let _IPPROTO_ICMP : Int = _ipproto_icmp_ffi()

///|
let _IPPROTO_ICMPV6 : Int = _ipproto_icmpv6_ffi()

///|
priv trait ToIpAddr {
  ip_name(self : Self) -> String raise
  to_socket_addr(self : Self) -> SocketAddr raise
  to_ipaddr(self : Self) -> IpAddr
}

///|
impl ToIpAddr for IpAddr with to_ipaddr(self : IpAddr) -> IpAddr = "%identity"

///|
impl ToIpAddr for Ipv4Addr with to_ipaddr(self : Ipv4Addr) -> IpAddr = "%identity"

///|
impl ToIpAddr for Ipv6Addr with to_ipaddr(self : Ipv6Addr) -> IpAddr = "%identity"

///|
fn IpAddr::to_ipv4addr(self : IpAddr) -> Ipv4Addr = "%identity"

///|
fn IpAddr::to_ipv6addr(self : IpAddr) -> Ipv6Addr = "%identity"

///|
extern "C" fn ipv4_addrlen_ffi() -> Int = "moonbitlang_ipv4_addrlen"

///|
extern "C" fn ipv6_addrlen_ffi() -> Int = "moonbitlang_ipv6_addrlen"

///|
#borrow(addr)
extern "C" fn get_ipaddr_detail_ffi(
  addr : IpAddr,
  cb : (Int, Int, Int, Int) -> Bool,
) -> Int = "moonbitlang_get_ip_addr_detail"

///|
#borrow(addr, bytes)
extern "C" fn get_ipv4_name_ffi(addr : Ipv4Addr, bytes : Bytes) -> Int = "moonbitlang_get_ipv4_name"

///|
#borrow(addr, bytes)
extern "C" fn get_ipv6_name_ffi(addr : Ipv6Addr, bytes : Bytes) -> Int = "moonbitlang_get_ipv6_name"

///|
extern "C" fn create_sockaddr_storage_ffi() -> IpAddr = "moonbitlang_create_sockaddr_storage"

///|
let _IP_V4_ADDRLEN : Int = ipv4_addrlen_ffi()

///|
let _IP_V6_ADDRLEN : Int = ipv6_addrlen_ffi()

///|
pub(all) enum Domain {
  IPv4
  IPv6
  // TODO: support Unix domain socket
  // Unix
} derive(Show)

///|
priv enum Type {
  Stream // SOCK_STREAM
  Datagram // SOCK_DGRAM
  // Raw // SOCK_RAW
}

///|
pub fn Domain::from_address(addr : SocketAddr) -> Domain {
  match addr {
    V4(_) => IPv4
    V6(_) => IPv6
  }
}

///|
fn Domain::inner(self : Domain) -> Int {
  match self {
    IPv4 => _AF_INET
    IPv6 => _AF_INET6
    // Unix => _AF_UNIX
  }
}

///|
fn Type::inner(self : Type) -> Int {
  match self {
    Stream => _SOCK_STREAM
    Datagram => _SOCK_DGRAM
    // Raw => _SOCK_RAW
  }
}

///|
impl ToIpAddr for IpAddr with to_socket_addr(self : IpAddr) -> SocketAddr raise {
  let mut family : Int = -1
  let status = get_ipaddr_detail_ffi(self, fn(
    family_val : Int,
    _port_val : Int,
    _flowinfo_val : Int,
    _scope_id_val : Int,
  ) {
    family = family_val
    return true
  })
  guard status >= 0 else { raise InvalidAddr }
  if family == _AF_INET6 {
    return SocketAddr::V6(self.to_ipv6addr())
  } else if family == _AF_INET {
    return SocketAddr::V4(self.to_ipv4addr())
  } else {
    raise InvalidAddr
  }
}

///|
impl ToIpAddr for IpAddr with ip_name(self : IpAddr) -> String raise {
  match self.to_socket_addr() {
    V4(addr) => addr.ip_name()
    V6(addr) => addr.ip_name()
  }
}

///|
impl ToIpAddr for Ipv4Addr with to_socket_addr(self : Ipv4Addr) -> SocketAddr raise {
  SocketAddr::V4(self)
}

///|
impl ToIpAddr for Ipv4Addr with ip_name(self : Ipv4Addr) -> String raise {
  let bytes = Bytes::make(_IP_V4_ADDRLEN, 0)
  let status = get_ipv4_name_ffi(self, bytes)
  guard status >= 0 else { raise InvalidAddr }
  let buffer = @buffer.new()
  for i = 0; bytes[i] != 0; i = i + 1 {
    buffer.write_byte(bytes[i])
  }
  return utf8_bytes_to_mbt_string(buffer.contents())
}

///|
impl ToIpAddr for Ipv6Addr with to_socket_addr(self : Ipv6Addr) -> SocketAddr raise {
  SocketAddr::V6(self)
}

///|
impl ToIpAddr for Ipv6Addr with ip_name(self : Ipv6Addr) -> String raise {
  let bytes = Bytes::make(_IP_V6_ADDRLEN, 0)
  let status = get_ipv6_name_ffi(self, bytes)
  guard status >= 0 else { raise InvalidAddr }
  let buffer = @buffer.new()
  for i = 0; bytes[i] != 0; i = i + 1 {
    buffer.write_byte(bytes[i])
  }
  return utf8_bytes_to_mbt_string(buffer.contents())
}
