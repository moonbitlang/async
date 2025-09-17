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
async test "one way" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (client_read_from_server, server_write_to_client) = @pipe.pipe()
    let (server_read_from_client, client_write_to_server) = @pipe.pipe()
    // server
    root.spawn_bg(fn() {
      defer {
        server_read_from_client.close()
        server_write_to_client.close()
      }
      let server = @tls.TLS::server_from_pair(
        server_read_from_client,
        server_write_to_client,
        private_key_file="test_keys/key.pem",
        private_key_type=PEM,
        certificate_file="test_keys/cert.pem",
        certificate_type=PEM,
      )
      defer server.close()
      let buf = FixedArray::make(1024, b'0')
      while server.read(buf) is n && n > 0 {
        let data = buf.unsafe_reinterpret_as_bytes()[0:n]
        log.write_string("server received: \{data}\n")
      } else {
        server.shutdown()
        // give some time for the client to received shutdown notification
        @async.sleep(50)
      }
    })
    // client
    root.spawn_bg(fn() {
      defer {
        client_read_from_server.close()
        client_write_to_server.close()
      }
      let client = @tls.TLS::client_from_pair(
        client_read_from_server,
        client_write_to_server,
        verify=false,
      )
      defer client.close()
      client.write(b"abcd")
      @async.sleep(50)
      client.write(b"efgh")
      @async.sleep(50)
      client.write(b"ijkl")
      client.shutdown()
      @async.sleep(50)
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|server received: b"\x61\x62\x63\x64"
      #|server received: b"\x65\x66\x67\x68"
      #|server received: b"\x69\x6a\x6b\x6c"
      #|
    ),
  )
}

///|
async test "echo" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (client_read_from_server, server_write_to_client) = @pipe.pipe()
    let (server_read_from_client, client_write_to_server) = @pipe.pipe()
    // server
    root.spawn_bg(fn() {
      defer {
        server_read_from_client.close()
        server_write_to_client.close()
      }
      let server = @tls.TLS::server_from_pair(
        server_read_from_client,
        server_write_to_client,
        private_key_file="test_keys/key.pem",
        private_key_type=PEM,
        certificate_file="test_keys/cert.pem",
        certificate_type=PEM,
      )
      defer server.close()
      let buf = FixedArray::make(1024, b'0')
      while server.read(buf) is n && n > 0 {
        let data = buf.unsafe_reinterpret_as_bytes()[0:n]
        log.write_string("server received: \{data}\n")
        server.write(data)
      } else {
        server.shutdown()
        // give some time for the client to received shutdown notification
        @async.sleep(50)
      }
    })
    // client
    root.spawn_bg(fn() {
      defer {
        client_read_from_server.close()
        client_write_to_server.close()
      }
      let client = @tls.TLS::client_from_pair(
        client_read_from_server,
        client_write_to_server,
        verify=false,
      )
      defer client.close()
      for data in [b"abcd", b"efgh", b"ijkl"] {
        client.write(data)
        assert_eq(client.read_exactly(4), data)
        @async.sleep(50)
      }
      client.shutdown()
      @async.sleep(50)
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|server received: b"\x61\x62\x63\x64"
      #|server received: b"\x65\x66\x67\x68"
      #|server received: b"\x69\x6a\x6b\x6c"
      #|
    ),
  )
}
