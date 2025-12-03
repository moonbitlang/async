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
/// IPv4 address + port number
struct Addr(Bytes) derive(Eq, Compare, Hash)

///|
pub extern "C" fn Addr::new(ip : UInt, port : Int) -> Addr = "moonbitlang_async_make_ip_addr"

///|
extern "C" fn Addr::empty(family : AddrFamily) -> Addr = "moonbitlang_async_make_empty_addr"

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
fn Addr::family(self : Addr) -> AddrFamily {
  if self.is_ipv6() {
    IPv6
  } else {
    IPv4
  }
}

///|
#borrow(addr)
extern "C" fn Addr::get_ipv6_bytes(addr : Addr) -> @c_buffer.Buffer = "moonbitlang_async_addr_get_ipv6_bytes"

///|
#borrow(addr)
extern "C" fn Addr::is_ipv6_wildcard(addr : Addr) -> Bool = "moonbitlang_async_addr_is_ipv6_wildcard"

///|
pub impl Show for Addr with output(self, logger) {
  if self.is_ipv6() {
    // IPv6 address format
    logger.write_char('[')
    write_ipv6_str(self.get_ipv6_bytes(), logger)
    logger..write_char(']')..write_char(':')..write_object(self.port())
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
pub suberror InvalidAddr derive(Show, ToJson)

///|
/// Parse a string into IPv4 or IPv6 address, format should be `ip:port` for IPv4 or `[ip]:port` for IPv6
// TODO: faster implementation
pub fn Addr::parse(src : String) -> Addr raise InvalidAddr {
  if src.has_prefix("[") {
    let (ip_bytes, port, _, _) = try_parse_ipv6(src)
    Addr::new_ipv6(ip_bytes, port)
  } else {
    // IPv4 format: ip:port
    let (ip, port) = try_parse_ipv4(src) catch { _ => raise InvalidAddr }
    guard 0 <= port && port < 65536 else { raise InvalidAddr }
    Addr::new(ip, port)
  }
}

///|
#external
priv type AddrInfo

///|
/// Convert AddrInfo to Addr(support both IPv4 and IPv6)
extern "C" fn AddrInfo::to_addr(self : AddrInfo, port : Int) -> Addr = "moonbitlang_async_addrinfo_to_addr"

///|
extern "C" fn AddrInfo::next(self : AddrInfo) -> AddrInfo = "moonbitlang_async_addrinfo_get_next"

///|
extern "C" fn AddrInfo::free(self : AddrInfo) = "freeaddrinfo"

///|
extern "C" fn gai_strerror(code : Int) -> @c_buffer.Buffer = "gai_strerror"

///|
extern "C" fn get_EAI_SYSTEM() -> Int = "moonbitlang_async_get_EAI_SYSTEM"

///|
#borrow(host, out)
extern "C" fn getaddrinfo_ffi(host : Bytes, out : Ref[AddrInfo]) -> Int = "moonbitlang_async_getaddrinfo"

///|
async fn getaddrinfo(host : StringView, context~ : String) -> AddrInfo {
  struct Job {
    host : Bytes
    out : Ref[AddrInfo]
    mut err : Int
    mut sys_err : Int
  }
  let host_bytes = @encoding/utf8.encode(host)
  let job : Job = {
    host: host_bytes,
    out: @ref.new(@c_buffer.null_ptr()),
    err: 0,
    sys_err: 0,
  }
  @event_loop.perform_job_in_worker(job, allow_cancel=true, job => {
    job.err = getaddrinfo_ffi(job.host, job.out)
    if job.err == get_EAI_SYSTEM() {
      job.sys_err = @os_error.get_errno()
    }
  })
  if job.sys_err != 0 {
    raise @os_error.OSError(job.sys_err, context~)
  }
  if job.err != 0 {
    let c_str = gai_strerror(job.err)
    let len = c_str.strlen()
    let bytes = FixedArray::make(len, b'\x00')
    c_str.blit_to_bytes(dst=bytes, offset=0, len~)
    let msg = @encoding/utf8.decode(bytes.unsafe_reinterpret_as_bytes())
    raise ResolveHostnameError(msg)
  }
  job.out.val
}

///|
/// Error message from failure in resolving a network hostname.
/// The content of the error message is platfrom-dependent,
/// so users should never depend on it.
pub suberror ResolveHostnameError String derive(Show, ToJson)

///|
pub(all) enum IpProtocolPreference {
  OnlyV4
  OnlyV6
  FavorV4
  FavorV6
  NoPreference
} derive(Show)

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
  let ai_root = getaddrinfo(host, context~)
  defer ai_root.free()
  let first_addr = ai_root.to_addr(port)

  // search for address with preferred protocol
  match protocol {
    FavorV4 | OnlyV4 => {
      if not(first_addr.is_ipv6()) {
        return first_addr
      }
      for ai = ai_root.next(); not(@c_buffer.ptr_is_null(ai)); ai = ai.next() {
        let addr = ai.to_addr(port)
        if not(addr.is_ipv6()) {
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
      for ai = ai_root.next(); not(@c_buffer.ptr_is_null(ai)); ai = ai.next() {
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
