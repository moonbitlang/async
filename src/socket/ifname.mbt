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
let global_ifname_socket : Ref[@fd_util.Fd] = {
  let context = "creating global socket object for interface name lookup"
  let sock = Ref(
    if @event_loop.platform is Linux {
      make_udp_socket(IPv4, multicast=false, context~) catch {
        err => abort(err.to_string())
      }
    } else {
      @fd_util.invalid_fd
    },
  )
  @event_loop.register_hook(
    init=() => {
      // In some tests there may be multiple event loops spawned in a single program run,
      // ensure the global socket object is valid after the last event loop disposed it
      if @event_loop.platform is Linux && !@fd_util.fd_is_valid(sock.val) {
        sock.val = make_udp_socket(IPv4, multicast=false, context~)
      }
    },
    exit=() => {
      guard @fd_util.fd_is_valid(sock.val) else {  }
      defer {
        sock.val = @fd_util.invalid_fd
      }
      @fd_util.close(
        sock.val,
        kind=Socket,
        context="closing global socket object for interface name lookup",
      )
    },
  )
  sock
}

///|
#borrow(name)
extern "C" fn if_nametoindex_ffi(
  global_sock : @fd_util.Fd,
  name : @os_string.OsString,
) -> UInt = "moonbitlang_async_if_nametoindex"

///|
extern "C" fn if_indextoname_ffi(
  global_sock : @fd_util.Fd,
  index : UInt,
) -> @os_string.OsString? = "moonbitlang_async_if_indextoname"

///|
#doc(hidden)
#internal(internal, "for internal use only")
pub fn if_nametoindex(name : StringView, context~ : String) -> UInt raise {
  let os_name = @os_string.encode(name)
  let index = if_nametoindex_ffi(global_ifname_socket.val, os_name)
  if index is 0 {
    @os_error.check_errno("\{context}: if_nametoindex(\{name.escape()})")
  }
  index
}

///|
#doc(hidden)
#internal(internal, "for internal use only")
pub fn if_indextoname(index : UInt, context~ : String) -> String raise {
  let name = if_indextoname_ffi(global_ifname_socket.val, index)
  guard name is Some(os_name) else {
    @os_error.check_errno("\{context}: if_indextoname(\{index})")
    panic()
  }
  os_name.to_string()
}
