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
test "main" {
  let log = StringBuilder::new()
  fn println(msg) -> Unit {
    log..write_string(msg)..write_string("\n")
  }

  let result = try? @udp_ping_pong.main_prog(println)
  log.write_string(result.to_string())
  inspect(
    log.to_string(),
    content=(
      #|client 0 sent: b"\x70\x69\x6e\x67"
      #|server received: b"\x70\x69\x6e\x67"
      #|server sent: b"\x70\x6f\x6e\x67"
      #|client 0 received: b"\x70\x6f\x6e\x67"
      #|client 1 sent: b"\x70\x6f\x6e\x67"
      #|server received: b"\x70\x6f\x6e\x67"
      #|server sent: b"\x70\x6f\x6e\x67"
      #|client 1 received: b"\x70\x6f\x6e\x67"
      #|client 2 sent: b"\x70\x69\x6e\x67"
      #|server received: b"\x70\x69\x6e\x67"
      #|server sent: b"\x70\x6f\x6e\x67"
      #|client 2 received: b"\x70\x6f\x6e\x67"
      #|client 3 sent: b"\x70\x69\x6e\x67"
      #|server received: b"\x70\x69\x6e\x67"
      #|server sent: b"\x70\x6f\x6e\x67"
      #|client 3 received: b"\x70\x6f\x6e\x67"
      #|client 4 sent: b"\x70\x6f\x6e\x67"
      #|server received: b"\x70\x6f\x6e\x67"
      #|server sent: b"\x70\x6f\x6e\x67"
      #|client 4 received: b"\x70\x6f\x6e\x67"
      #|client 5 sent: b"\x70\x69\x6e\x67"
      #|server received: b"\x70\x69\x6e\x67"
      #|server sent: b"\x70\x6f\x6e\x67"
      #|client 5 received: b"\x70\x6f\x6e\x67"
      #|client 6 sent: b"\x65\x78\x69\x74"
      #|server received: b"\x65\x78\x69\x74"
      #|server sent: b"\x70\x6f\x6e\x67"
      #|server initiate terminate
      #|server terminate: ServerTerminate
      #|Err(ServerTerminate)
    ),
  )
}
