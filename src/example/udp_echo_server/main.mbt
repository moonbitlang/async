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
fn main_prog() -> Unit raise {
  @async.with_event_loop(fn(root) {
    let server = @socket.UDP::new()
    defer server.close()
    server.bind(@socket.Addr::parse("0.0.0.0:4200"))
    for {
      let buf = FixedArray::make(1024, b'0')
      let (n, addr) = server.recvfrom(buf)
      root.spawn_bg(fn() {
        let buf = buf.unsafe_reinterpret_as_bytes()
        server.sendto(buf[0:n].to_bytes(), addr)
      })
    }
  })
}

///|
fn main {
  main_prog() catch {
    err => println("server exit with error \{err}")
  }
}
