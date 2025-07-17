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
#external
type AddrInfoResults

///|
extern "C" fn _af_inet_ffi() -> Int = "moonbitlang_AF_INET_ffi"

///|
extern "C" fn _af_inet6_ffi() -> Int = "moonbitlang_AF_INET6_ffi"

///|
extern "C" fn _af_unix_ffi() -> Int = "moonbitlang_AF_UNIX_ffi"

///|
extern "C" fn _af_unspec_ffi() -> Int = "moonbitlang_AF_UNSPEC_ffi"

///|
extern "C" fn _sock_stream_ffi() -> Int = "moonbitlang_SOCK_STREAM_ffi"

///|
extern "C" fn _sock_dgram_ffi() -> Int = "moonbitlang_SOCK_DGRAM_ffi"

///|
extern "C" fn _sock_raw_ffi() -> Int = "moonbitlang_SOCK_RAW_ffi"

///|
extern "C" fn _ipproto_tcp_ffi() -> Int = "moonbitlang_IPPROTO_TCP_ffi"

///|
extern "C" fn _ipproto_udp_ffi() -> Int = "moonbitlang_IPPROTO_UDP_ffi"

///|
extern "C" fn _ipproto_icmp_ffi() -> Int = "moonbitlang_IPPROTO_ICMP_ffi"

///|
extern "C" fn _ipproto_icmpv6_ffi() -> Int = "moonbitlang_IPPROTO_ICMPV6_ffi"

///|
extern "C" fn _sol_socket_ffi() -> Int = "moonbitlang_SOL_SOCKET_ffi"

///|
extern "C" fn _so_reuseaddr_ffi() -> Int = "moonbitlang_SO_REUSEADDR_ffi"

///|
extern "C" fn _so_keepalive_ffi() -> Int = "moonbitlang_SO_KEEPALIVE_ffi"

///|
extern "C" fn _so_rcvbuf_ffi() -> Int = "moonbitlang_SO_RCVBUF_ffi"

///|
extern "C" fn _so_sndbuf_ffi() -> Int = "moonbitlang_SO_SNDBUF_ffi"

///|
extern "C" fn _shut_rd_ffi() -> Int = "moonbitlang_SHUT_RD_ffi"

///|
extern "C" fn _shut_wr_ffi() -> Int = "moonbitlang_SHUT_WR_ffi"

///|
extern "C" fn _shut_rdwr_ffi() -> Int = "moonbitlang_SHUT_RDWR_ffi"

///|
extern "C" fn _ai_flag_ai_passive_ffi() -> Int = "moonbitlang_FLAG_AI_PASSIVE_ffi"

///|
extern "C" fn _ai_flag_ai_canonname_ffi() -> Int = "moonbitlang_FLAG_AI_CANONNAME_ffi"

///|
extern "C" fn _ai_flag_ai_all_ffi() -> Int = "moonbitlang_FLAG_AI_ALL_ffi"

///|
extern "C" fn _ai_flag_ai_numerichost_ffi() -> Int = "moonbitlang_FLAG_AI_NUMERICHOST_ffi"

///|
extern "C" fn _ai_flag_ai_numericserv_ffi() -> Int = "moonbitlang_FLAG_AI_NUMERICSERV_ffi"

///|
extern "C" fn _ai_flag_ai_addrconfig_ffi() -> Int = "moonbitlang_FLAG_AI_ADDRCONFIG_ffi"

///|
extern "C" fn _ai_flag_ai_v4mapped_ffi() -> Int = "moonbitlang_FLAG_AI_V4MAPPED_ffi"

///|
extern "C" fn _socket_opt_level_sol_socket_ffi() -> Int = "moonbitlang_SOCKOPT_LEVEL_SOL_SOCKET_ffi"

///|
extern "C" fn _socket_opt_level_ipproto_ip_ffi() -> Int = "moonbitlang_SOCKOPT_LEVEL_IPPROTO_IP_ffi"

///|
extern "C" fn _socket_opt_level_ipproto_tcp_ffi() -> Int = "moonbitlang_SOCKOPT_LEVEL_IPPROTO_TCP_ffi"

///|
extern "C" fn _socket_opt_level_ipproto_udp_ffi() -> Int = "moonbitlang_SOCKOPT_LEVEL_IPPROTO_UDP_ffi"

///|
extern "C" fn _socket_opt_level_ipproto_icmp_ffi() -> Int = "moonbitlang_SOCKOPT_LEVEL_IPPROTO_ICMP_ffi"

///|
extern "C" fn _socket_opt_level_ipproto_icmpv6_ffi() -> Int = "moonbitlang_SOCKOPT_LEVEL_IPPROTO_ICMPV6_ffi"

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
let _SOL_SOCKET : Int = _sol_socket_ffi()

///|
let _SO_REUSEADDR : Int = _so_reuseaddr_ffi()

///|
let _SO_KEEPALIVE : Int = _so_keepalive_ffi()

///|
let _SO_RCVBUF : Int = _so_rcvbuf_ffi()

///|
let _SO_SNDBUF : Int = _so_sndbuf_ffi()

///|
let _SHUT_RD : Int = _shut_rd_ffi()

///|
let _SHUT_WR : Int = _shut_wr_ffi()

///|
let _SHUT_RDWR : Int = _shut_rdwr_ffi()

///|
let _AI_FLAG_PASSIVE : Int = _ai_flag_ai_passive_ffi()

///|
let _AI_FLAG_CANONNAME : Int = _ai_flag_ai_canonname_ffi()

///|
let _AI_FLAG_ALL : Int = _ai_flag_ai_all_ffi()

///|
let _AI_FLAG_NUMERICHOST : Int = _ai_flag_ai_numerichost_ffi()

///|
let _AI_FLAG_NUMERICSERV : Int = _ai_flag_ai_numericserv_ffi()

///|
let _AI_FLAG_ADDRCONFIG : Int = _ai_flag_ai_addrconfig_ffi()

///|
let _AI_FLAG_V4MAPPED : Int = _ai_flag_ai_v4mapped_ffi()

///|
let _SOCKOPT_LEVEL_SOL_SOCKET : Int = _socket_opt_level_sol_socket_ffi()

///|
let _SOCKOPT_LEVEL_IPPROTO_IP : Int = _socket_opt_level_ipproto_ip_ffi()

///|
let _SOCKOPT_LEVEL_IPPROTO_TCP : Int = _socket_opt_level_ipproto_tcp_ffi()

///|
let _SOCKOPT_LEVEL_IPPROTO_UDP : Int = _socket_opt_level_ipproto_udp_ffi()

///|
let _SOCKOPT_LEVEL_IPPROTO_ICMP : Int = _socket_opt_level_ipproto_icmp_ffi()

///|
let _SOCKOPT_LEVEL_IPPROTO_ICMPV6 : Int = _socket_opt_level_ipproto_icmpv6_ffi()

///|
pub struct AddrInfo {
  family : Int
  socktype : Int
  protocol : Int
  addr : IpAddr
  canonname : String?
}

///|
pub(open) trait ToIpAddr {
  ip_name(self : Self) -> String raise
  to_socket_addr(self : Self) -> SocketAddr raise
  to_ipaddr(self : Self) -> IpAddr
}

///|
priv trait RawPointer {
  is_null(self : Self) -> Bool
}

///|
pub(open) trait ToCString {
  to_cstring(self : Self) -> Bytes
}

///|
pub impl ToIpAddr for IpAddr with to_ipaddr(self : IpAddr) -> IpAddr = "%identity"

///|
pub impl ToIpAddr for Ipv4Addr with to_ipaddr(self : Ipv4Addr) -> IpAddr = "%identity"

///|
pub impl ToIpAddr for Ipv6Addr with to_ipaddr(self : Ipv6Addr) -> IpAddr = "%identity"

///|
fn IpAddr::to_ipv4addr(self : IpAddr) -> Ipv4Addr = "%identity"

///|
fn IpAddr::to_ipv6addr(self : IpAddr) -> Ipv6Addr = "%identity"

///|
#borrow(ptr)
extern "C" fn addrinfo_is_null_pointer_ffi(ptr : AddrInfoResults) -> Bool = "moonbitlang_is_null_pointer"

///|
extern "C" fn ipv4_addrlen_ffi() -> Int = "moonbitlang_ipv4_addrlen_ffi"

///|
extern "C" fn ipv6_addrlen_ffi() -> Int = "moonbitlang_ipv6_addrlen_ffi"

///|
#borrow(addr)
extern "C" fn get_ip_name_ffi(
  addr : IpAddr,
  cb : (Int, Int, Int, Int) -> Bool
) -> Int = "moonbitlang_get_ip_name_ffi"

///|
#borrow(addr, bytes)
extern "C" fn get_ipv4_name_ffi(addr : Ipv4Addr, bytes : Bytes) -> Int = "moonbitlang_get_ipv4_name_ffi"

///|
#borrow(addr, bytes)
extern "C" fn get_ipv6_name_ffi(addr : Ipv6Addr, bytes : Bytes) -> Int = "moonbitlang_get_ipv6_name_ffi"

///|
extern "C" fn create_sockaddr_storage_ffi() -> IpAddr = "moonbitlang_create_sockaddr_storage_ffi"

///|
let _IP_V4_ADDRLEN : Int = ipv4_addrlen_ffi()

///|
let _IP_V6_ADDRLEN : Int = ipv6_addrlen_ffi()

///|
pub(all) enum Domain {
  IPv4
  IPv6
  Unix
} derive(Show)

///|
pub fn Domain::from_address(addr : SocketAddr) -> Domain {
  match addr {
    V4(_) => IPv4
    V6(_) => IPv6
  }
}

///|
pub(all) enum Type {
  Stream // SOCK_STREAM
  Datagram // SOCK_DGRAM
  Raw // SOCK_RAW
} derive(Show)

///|
pub(open) trait ToType {
  to_type(self : Self) -> Type raise
}

///|
pub impl ToType for Type with to_type(self : Type) -> Type {
  self
}

///|
pub(all) enum Protocol {
  TCP // IPPROTO_TCP
  UDP // IPPROTO_UDP
  ICMPV4 // IPPROTO_ICMP
  ICMPV6 // IPPROTO_ICMPV6
} derive(Show)

///|
pub(all) enum Shutdown {
  Read // SHUT_RD
  Write // SHUT_WR
  Both // SHUT_RDWR
} derive(Show)

///|
pub fn Domain::inner(self : Domain) -> Int {
  match self {
    IPv4 => _AF_INET
    IPv6 => _AF_INET6
    Unix => _AF_UNIX
  }
}

///|
pub fn Type::inner(self : Type) -> Int {
  match self {
    Stream => _SOCK_STREAM
    Datagram => _SOCK_DGRAM
    Raw => _SOCK_RAW
  }
}

///|
pub fn Protocol::inner(self : Protocol) -> Int {
  match self {
    TCP => _IPPROTO_TCP
    UDP => _IPPROTO_UDP
    ICMPV4 => _IPPROTO_ICMP
    ICMPV6 => _IPPROTO_ICMPV6
  }
}

///|
pub fn Shutdown::inner(self : Shutdown) -> Int {
  match self {
    Read => _SHUT_RD // SHUT_RD
    Write => _SHUT_WR // SHUT_WR
    Both => _SHUT_RDWR // SHUT_RDWR
  }
}

///|
pub impl ToSocketAddrs for String with to_socket_addr(self : String) -> Iter[
  SocketAddr,
] raise {
  if (try? parse_address(self)) is Ok(addr) {
    return [addr].iter()
  }
  let (host, port) = match self.rev_find(":") {
    Some(last_colon) if last_colon < self.length() => {
      let ip_str = self.substring(end=last_colon)
      let port_str = self.substring(start=last_colon + 1)
      (ip_str, parse_port(port_str))
    }
    None => (self, 80) // No port specified, default to 80
    _ => raise InvalidAddr
  }
  getaddrinfo(
    host,
    port.to_string(),
    0,
    Domain::Unix,
    Type::Stream,
    Protocol::TCP,
  )
  .iter()
  .map(fn(info : AddrInfo) {
    if info.family == _AF_INET6 {
      Some(SocketAddr::V6(info.addr.to_ipv6addr()))
    } else {
      Some(SocketAddr::V4(info.addr.to_ipv4addr()))
    }
  })
  .filter(r => !r.is_empty())
  .map(r => r.unwrap())
}

///|
impl RawPointer for AddrInfoResults with is_null(self : AddrInfoResults) -> Bool {
  return addrinfo_is_null_pointer_ffi(self)
}

///|
pub impl ToCString for String with to_cstring(self : String) -> Bytes {
  mbt_string_to_utf8_bytes(self, true)
}

///|
pub impl ToIpAddr for IpAddr with to_socket_addr(self : IpAddr) -> SocketAddr raise {
  let mut family : Int = -1
  let status = get_ip_name_ffi(self, fn(
    family_val : Int,
    _port_val : Int,
    _flowinfo_val : Int,
    _scope_id_val : Int
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
    println("Unsupported address family: \{family}")
    raise InvalidAddr
  }
}

///|
pub impl ToIpAddr for IpAddr with ip_name(self : IpAddr) -> String raise {
  match self.to_socket_addr() {
    V4(addr) => addr.ip_name()
    V6(addr) => addr.ip_name()
  }
}

///|
pub impl ToIpAddr for Ipv4Addr with to_socket_addr(self : Ipv4Addr) -> SocketAddr raise {
  SocketAddr::V4(self)
}

///|
pub impl ToIpAddr for Ipv4Addr with ip_name(self : Ipv4Addr) -> String raise {
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
pub impl ToIpAddr for Ipv6Addr with to_socket_addr(self : Ipv6Addr) -> SocketAddr raise {
  SocketAddr::V6(self)
}

///|
pub impl ToIpAddr for Ipv6Addr with ip_name(self : Ipv6Addr) -> String raise {
  let bytes = Bytes::make(_IP_V6_ADDRLEN, 0)
  let status = get_ipv6_name_ffi(self, bytes)
  guard status >= 0 else { raise InvalidAddr }
  let buffer = @buffer.new()
  for i = 0; bytes[i] != 0; i = i + 1 {
    buffer.write_byte(bytes[i])
  }
  return utf8_bytes_to_mbt_string(buffer.contents())
}

///|
extern "C" fn getaddrinfo_make_ffi(
  hostname : Bytes,
  service : Bytes,
  ai_flags : Int,
  ai_family : Int,
  ai_socktype : Int,
  ai_protocol : Int
) -> AddrInfoResults = "moonbitlang_getaddrinfo_make_ffi"

///|
extern "C" fn addrinfo_results_iterate_ffi(
  addr_info : AddrInfoResults,
  cb : (Int, Int, Int, Int, IpAddr) -> Bool
) -> Bool = "moonbitlang_addrinfo_results_iterate_ffi"

///|
pub fn AddrInfoResults::iter(self : AddrInfoResults) -> Iter[AddrInfo] {
  Iter::new(fn(yield_ : (AddrInfo) -> IterResult) {
    if addrinfo_results_iterate_ffi(self, fn(
        _,
        family : Int,
        socktype : Int,
        protocol : Int,
        addr : IpAddr
      ) {
        match yield_({ family, socktype, protocol, addr, canonname: None }) {
          IterEnd => true
          IterContinue => false
        }
      }) {
      return IterEnd
    } else {
      return IterContinue
    }
  })
}

///|
pub fn[H : ToCString, S : ToCString] getaddrinfo(
  hostname : H,
  service : S,
  ai_flags : Int,
  ai_family : Domain,
  ai_socktype : Type,
  ai_protocol : Protocol
) -> AddrInfoResults raise InvalidAddr {
  let service = service.to_cstring()
  let addr_info = getaddrinfo_make_ffi(
    hostname.to_cstring(),
    service,
    ai_flags,
    ai_family.inner(),
    ai_socktype.inner(),
    ai_protocol.inner(),
  )
  if addr_info.is_null() {
    raise InvalidAddr
  }
  return addr_info
}
