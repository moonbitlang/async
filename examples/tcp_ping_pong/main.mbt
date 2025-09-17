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
suberror ServerTerminate derive(Show)

///|
let port = 4201

///|
pub(all) struct Printer((String) -> Unit)

///|
async fn server(println : Printer) -> Unit {
  @async.with_task_group(fn(group) {
    let server = @socket.TCPServer::new(@socket.Addr::parse("0.0.0.0:\{port}"))
    defer server.close()
    try {
      for {
        let (conn, _) = server.accept()
        println("received new connection")
        group.spawn_bg(fn() {
          defer conn.close()
          let buf = FixedArray::make(1024, b'0')
          while conn.read(buf) is n && n > 0 {
            @async.sleep(10)
            let msg = buf.unsafe_reinterpret_as_bytes()[0:n]
            println("server received: \{msg}")
            let reply = b"pong"
            conn.write(reply)
            println("server sent: \{reply}")
            if msg == b"exit" {
              println("server initiate terminate")
              @async.sleep(20)
              raise ServerTerminate
            }
          } else {
            println("server: connection closed by peer")
          }
        })
      }
    } catch {
      err => {
        println("server terminate: \{err}")
        raise err
      }
    }
  })
}

///|
async fn client(println : Printer, id : Int, msg : Bytes) -> Unit {
  let conn = @socket.TCP::connect(@socket.Addr::parse("127.0.0.1:\{port}"))
  defer conn.close()
  // The sleep here is used to make test result stable and portable,
  // because this message is in race condition
  // with server side "received connection" message
  @async.sleep(10)
  println("client \{id}: connection established")
  conn.write(msg)
  println("client \{id} sent: \{msg}")
  let buf = FixedArray::make(1024, b'0')
  if conn.read(buf) is n && n > 0 {
    @async.sleep(10)
    let msg = buf.unsafe_reinterpret_as_bytes()[0:n]
    println("client \{id} received: \{msg}")
  } else {
    println("client \{id}: connection closed by peer")
  }
}

///|
pub async fn main_prog(println : Printer) -> Unit {
  @async.with_task_group(fn(root) {
    root.spawn_bg(() => server(println))
    root.spawn_bg(fn() {
      @async.with_task_group(fn(ctx) {
        for i in 0..<6 {
          let msg = if i % 3 == 1 { b"pong" } else { b"ping" }
          ctx.spawn_bg(() => client(println, i, msg))
          @async.sleep(100)
        }
      })
      root.spawn_bg(() => client(println, 6, b"exit"))
    })
  }) catch {
    ServerTerminate => ()
    err => raise err
  }
}

///|
async fn main {
  main_prog(println)
}
