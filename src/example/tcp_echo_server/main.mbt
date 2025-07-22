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
    let listen_sock = @socket.TCP::new()
    defer listen_sock.close()
    listen_sock..bind(@socket.SocketAddr::parse("0.0.0.0:4200"))..listen()
    for {
      let (conn, addr) = listen_sock.accept()
      println("received new connection from \{addr}")
      root.spawn_bg(fn() {
        defer conn.close()
        let buf = FixedArray::make(1024, b'0')
        while conn.recv(buf) is n && n > 0 {
          let buf = buf.unsafe_reinterpret_as_bytes()
          conn.send(buf[0:n].to_bytes())
        }
        println("connection closed")
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
