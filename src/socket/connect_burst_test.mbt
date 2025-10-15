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
suberror ServerTerminate

///|
async fn server(addr : String) -> Int {
  let server = @socket.TcpServer::new(@socket.Addr::parse(addr))
  defer server.close()
  let mut num_connection = 0
  try
    @async.with_task_group(fn(group) {
      for {
        let (conn, _) = server.accept()
        num_connection += 1
        group.spawn_bg(fn() {
          defer conn.close()
          let buf = FixedArray::make(1024, b'0')
          while conn.read(buf) is n && n > 0 {
            let msg = buf.unsafe_reinterpret_as_bytes()[0:n]
            if msg == b"exit" {
              @async.sleep(20)
              raise ServerTerminate
            }
          }
        })
      }
    })
  catch {
    ServerTerminate => num_connection
    err => raise err
  } noraise {
    (_ : Unit) => panic()
  }
}

///|
async fn client(msg : Bytes, addr : String) -> Unit {
  let conn = @socket.Tcp::connect(@socket.Addr::parse(addr))
  defer conn.close()
  conn.write(msg)
}

///|
async test "connection burst" {
  let mut result = 0
  let port = 4206
  @async.with_task_group(fn(root) {
    root.spawn_bg(() => result = server("0.0.0.0:\{port}"))
    root.spawn_bg(fn() {
      @async.with_task_group(fn(ctx) {
        for _ in 0..<6 {
          ctx.spawn_bg(() => client(b"ping", "127.0.0.1:\{port}"))
        }
      })
      root.spawn_bg(() => client(b"exit", "127.0.0.1:\{port}"))
    })
  })
  inspect(result, content="7")
}

///|
async test "connection burst with ipv6" {
  let mut result = 0
  let port = 4207
  @async.with_task_group(fn(root) {
    root.spawn_bg(() => result = server("[::]:\{port}"))
    root.spawn_bg(fn() {
      @async.with_task_group(fn(ctx) {
        for _ in 0..<6 {
          ctx.spawn_bg(() => client(b"ping", "[::1]:\{port}"))
        }
      })
      root.spawn_bg(() => client(b"exit", "[::1]:\{port}"))
    })
  })
  inspect(result, content="7")
}
