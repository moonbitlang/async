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
test "read_exactly" {
  let port = 4203
  let buf = StringBuilder::new()
  fn log(msg) {
    buf..write_string(msg).write_char('\n')
  }

  @async.with_event_loop(fn(root) {
    // server
    root.spawn_bg(fn() {
      let listen_sock = @socket.TCP::new()
      try {
        listen_sock..bind(@socket.Addr::parse("127.0.0.1:\{port}"))..listen()
        let (conn, _) = listen_sock.accept()
        try {
          let msg1 = conn.recv_exactly(4)
          log("first message: \{msg1}")
          let msg2 = conn.recv_exactly(4)
          log("second message: \{msg2}")
          let msg3 = conn.recv_exactly(4)
          log("third message: \{msg3}")
        } catch {
          err => {
            conn.close()
            raise err
          }
        } noraise {
          _ => {
            // let the client close first to avoid socket entering `TIME_WAIT` state,
            // occupying the address.
            @async.sleep(50)
            conn.close()
          }
        }
      } catch {
        err => {
          listen_sock.close()
          raise err
        }
      } noraise {
        _ => listen_sock.close()
      }
    })
    // client
    root.spawn_bg(fn() {
      let conn = @socket.TCP::new()
      conn.connect(@socket.Addr::parse("127.0.0.1:\{port}"))
      conn.send([1, 2, 3, 4, 5, 6])
      log("first message sent")
      @async.sleep(200)
      conn.send([7, 8, 9, 10, 11, 12])
      log("second message sent")
      conn.close()
    })
  })
  inspect(
    buf.to_string(),
    content=(
      #|first message sent
      #|first message: b"\x01\x02\x03\x04"
      #|second message sent
      #|second message: b"\x05\x06\x07\x08"
      #|third message: b"\x09\x0a\x0b\x0c"
      #|
    ),
  )
}

///|
test "read_exactly failure" {
  let port = 4204
  let buf = StringBuilder::new()
  fn log(msg) {
    buf..write_string(msg).write_char('\n')
  }

  let result = try? @async.with_event_loop(fn(root) {
      // server
      root.spawn_bg(fn() {
        let listen_sock = @socket.TCP::new()
        try {
          listen_sock..bind(@socket.Addr::parse("127.0.0.1:\{port}"))..listen()
          let (conn, _) = listen_sock.accept()
          try {
            let msg1 = conn.recv_exactly(4)
            log("first message: \{msg1}")
            let msg2 = conn.recv_exactly(4)
            log("second message: \{msg2}")
            let msg3 = conn.recv_exactly(4)
            log("third message: \{msg3}")
          } catch {
            err => {
              conn.close()
              raise err
            }
          } noraise {
            _ => {
              // let the client close first to avoid socket entering `TIME_WAIT` state,
              // occupying the address.
              @async.sleep(50)
              conn.close()
            }
          }
        } catch {
          err => {
            listen_sock.close()
            raise err
          }
        } noraise {
          _ => listen_sock.close()
        }
      })
      // client
      root.spawn_bg(fn() {
        let conn = @socket.TCP::new()
        conn.connect(@socket.Addr::parse("127.0.0.1:\{port}"))
        conn.send([1, 2, 3, 4, 5, 6])
        log("first message sent")
        @async.sleep(200)
        conn.close()
      })
    })
  log(result.to_string())
  inspect(
    buf.to_string(),
    content=(
      #|first message sent
      #|first message: b"\x01\x02\x03\x04"
      #|Err(ConnectionClosed)
      #|
    ),
  )
}
