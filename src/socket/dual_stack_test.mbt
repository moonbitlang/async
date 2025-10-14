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
let all_protocol_preferences : FixedArray[@socket.IPProtocolPreference] = [
  @socket.Favor_V4,
  @socket.Only_V4,
  @socket.Favor_V6,
  @socket.Only_V6,
]

///|
async test "Only_V4 server" {
  let log = StringBuilder::new()
  let port = 4209
  @async.with_task_group(fn(root) {
    root.spawn_bg(no_wait=true, fn() {
      let server = @socket.TCPServer::new(
        @socket.Addr::parse("0.0.0.0:\{port}"),
      )
      for {
        let (conn, addr) = server.accept()
        defer conn.close()
        let addr_str = addr.to_string()
        guard addr_str.rev_find(":") is Some(ip_end)
        let ip = addr_str[:ip_end]
        let msg = conn.read_all().text()
        log.write_string("server received \{repr(msg)} from \{ip}\n")
      }
    })
    async fn client(protocol) {
      let conn = @socket.TCP::connect_to_host("localhost", port~, protocol~)
      defer conn.close()
      conn.write("message")
    }

    for protocol in all_protocol_preferences {
      let result = try? client(protocol)
      @async.sleep(100)
      log.write_string("client(\{protocol}): \{result}\n")
    }
    // give some time for the server to process the last connection
    @async.sleep(300)
  })
  inspect(
    log.to_string(),
    content=(
      #|server received "message" from 127.0.0.1
      #|client(Favor_V4): Ok(())
      #|server received "message" from 127.0.0.1
      #|client(Only_V4): Ok(())
      #|server received "message" from 127.0.0.1
      #|client(Favor_V6): Ok(())
      #|client(Only_V6): Err(OSError("@socket.TCP::connect: Connection refused"))
      #|
    ),
  )
}

///|
async test "Only_V6 server" {
  let log = StringBuilder::new()
  let port = 4210
  @async.with_task_group(fn(root) {
    root.spawn_bg(no_wait=true, fn() {
      let server = @socket.TCPServer::new(@socket.Addr::parse("[::]:\{port}"))
      for {
        let (conn, addr) = server.accept()
        defer conn.close()
        let addr_str = addr.to_string()
        guard addr_str.rev_find(":") is Some(ip_end)
        let ip = addr_str[:ip_end]
        let msg = conn.read_all().text()
        log.write_string("server received \{repr(msg)} from \{ip}\n")
      }
    })
    async fn client(protocol) {
      let conn = @socket.TCP::connect_to_host("localhost", port~, protocol~)
      defer conn.close()
      conn.write("message")
    }

    for protocol in all_protocol_preferences {
      let result = try? client(protocol)
      @async.sleep(100)
      log.write_string("client(\{protocol}): \{result}\n")
    }
    // give some time for the server to process the last connection
    @async.sleep(300)
  })
  inspect(
    log.to_string(),
    content=(
      #|server received "message" from [::1]
      #|client(Favor_V4): Ok(())
      #|client(Only_V4): Err(OSError("@socket.TCP::connect: Connection refused"))
      #|server received "message" from [::1]
      #|client(Favor_V6): Ok(())
      #|server received "message" from [::1]
      #|client(Only_V6): Ok(())
      #|
    ),
  )
}

///|
async test "dual stack server" {
  let log = StringBuilder::new()
  let port = 4211
  @async.with_task_group(fn(root) {
    root.spawn_bg(no_wait=true, fn() {
      let server = @socket.TCPServer::new_dual_stack(port)
      for {
        let (conn, addr) = server.accept()
        defer conn.close()
        let addr_str = addr.to_string()
        guard addr_str.rev_find(":") is Some(ip_end)
        let ip = addr_str[:ip_end]
        let msg = conn.read_all().text()
        log.write_string("server received \{repr(msg)} from \{ip}\n")
      }
    })
    async fn client(protocol) {
      let conn = @socket.TCP::connect_to_host("localhost", port~, protocol~)
      defer conn.close()
      conn.write("message")
    }

    for protocol in all_protocol_preferences {
      let result = try? client(protocol)
      @async.sleep(100)
      log.write_string("client(\{protocol}): \{result}\n")
    }
    // give some time for the server to process the last connection
    @async.sleep(300)
  })
  inspect(
    log.to_string(),
    content=(
      #|server received "message" from [::ffff:127.0.0.1]
      #|client(Favor_V4): Ok(())
      #|server received "message" from [::ffff:127.0.0.1]
      #|client(Only_V4): Ok(())
      #|server received "message" from [::1]
      #|client(Favor_V6): Ok(())
      #|server received "message" from [::1]
      #|client(Only_V6): Ok(())
      #|
    ),
  )
}
