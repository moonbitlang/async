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
  @async.with_event_loop(fn(ctx) {
    let listen_sock = make_tcp_socket()
    bind(listen_sock, "0.0.0.0", 4200)
    listen(listen_sock)
    for {
      let conn = accept(listen_sock)
      println("received new connection \{conn}")
      ctx.spawn(fn() {
        let buf = Bytes::make(1024, 0)
        while recv(conn, buf) is n && n > 0 {
          let _ = send(conn, buf[0:n].to_bytes())

        }
        println("connection \{conn} closed")
      })
      |> ignore
    }
  })
}

///|
fn main {
  main_prog() catch {
    err => println("server exit with error \{err}")
  }
}
