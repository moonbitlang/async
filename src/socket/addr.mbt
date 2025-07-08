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
type Addr Bytes

///|
pub extern "C" fn Addr::new(ip : UInt, port : Int) -> Addr = "make_ip_addr"

///|
#borrow(addr)
pub extern "C" fn Addr::ip(addr : Addr) -> UInt = "ip_addr_get_ip"

///|
#borrow(addr)
pub extern "C" fn Addr::port(addr : Addr) -> Int = "ip_addr_get_port"

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
