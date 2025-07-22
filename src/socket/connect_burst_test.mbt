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
let port = 4205

///|
async fn server(ip : String) -> Int raise {
  let mut num_connection = 0
  let addr = @socket.SocketAddr::parse("\{ip}:\{port}")
  let domain = Domain::from_address(addr)
  let listen_sock = @socket.TCP::new(domain~)
  try
    @async.with_task_group(fn(group) {
      listen_sock..bind(addr)..listen()
      defer listen_sock.close()
      for {
        let (conn, _) = listen_sock.accept()
        num_connection += 1
        group.spawn_bg(fn() {
          defer conn.close()
          let buf = FixedArray::make(1024, b'0')
          while conn.recv(buf) is n && n > 0 {
            let msg = buf.unsafe_reinterpret_as_bytes()[0:n]
            if msg == b"exit" {
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
async fn client(ip : String, msg : Bytes) -> Unit raise {
  let addr = @socket.SocketAddr::parse("\{ip}:\{port}")
  let domain = Domain::from_address(addr)
  let conn = @socket.TCP::new(domain~)
  defer conn.close()
  conn.connect(addr)
  conn.send(msg)
}

///|
test "connection burst" {
  let log = StringBuilder::new()
  let mut result = 0
  let ip = "127.0.0.1"
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(() => result = server(ip))
      root.spawn_bg(fn() {
        @async.with_task_group(fn(ctx) {
          for _ in 0..<6 {
            ctx.spawn_bg(() => client(ip, b"ping"))
          }
        })
        root.spawn_bg(() => client(ip, b"exit"))
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

///|
test "connection burst with ipv6" {
  let log = StringBuilder::new()
  let mut result = 0
  let ip = "[::1]"
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(() => result = server(ip))
      root.spawn_bg(fn() {
        @async.with_task_group(fn(ctx) {
          for _ in 0..<6 {
            ctx.spawn_bg(() => client(ip, b"ping"))
          }
        })
        root.spawn_bg(() => client(ip, b"exit"))
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
