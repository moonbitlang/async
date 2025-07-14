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
let port = 4204

///|
async fn server() -> Int raise {
  let listen_sock = @socket.TCP::new()
  let mut num_connection = 0
  try
    @async.with_task_group(fn(group) {
      listen_sock..bind(@socket.Addr::parse("0.0.0.0:\{port}"))..listen()
      for {
        let (conn, _) = listen_sock.accept()
        num_connection += 1
        group.spawn_bg(fn() {
          let buf = FixedArray::make(1024, b'0')
          try {
            while conn.recv(buf) is n && n > 0 {
              let msg = buf.unsafe_reinterpret_as_bytes()[0:n]
              if msg == b"exit" {
                raise ServerTerminate
              }
            }
            conn.close()
          } catch {
            err => {
              conn.close()
              raise err
            }
          }
        })
      }
    })
  catch {
    ServerTerminate => {
      listen_sock.close()
      num_connection
    }
    err => {
      listen_sock.close()
      raise err
    }
  } noraise {
    (_ : Unit) => panic()
  }
}

///|
async fn client(msg : Bytes) -> Unit raise {
  let conn = @socket.TCP::new()
  conn.connect(@socket.Addr::parse("127.0.0.1:\{port}"))
  conn.send(msg)
  conn.close()
}

///|
test "connection burst" {
  let log = StringBuilder::new()
  let mut result = 0
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(() => result = server())
      root.spawn_bg(fn() {
        @async.with_task_group(fn(ctx) {
          for _ in 0..<6 {
            ctx.spawn_bg(() => client(b"ping"))
          }
        })
        root.spawn_bg(() => client(b"exit"))
      })
    }),
  )
  log.write_string("\n")
  log.write_object(result)
  inspect(
    log.to_string(),
    content=(
      #|Ok(())
      #|7
    ),
  )
}
