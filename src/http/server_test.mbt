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
async test "do not reuse passthrough connection" {
  @async.with_task_group <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr.port()
    group.spawn_bg(no_wait=true) <| () => {
      defer server.close()
      server.run_forever() <| ((_, _, conn) => {
        conn..send_response(200, "OK").end_response()
        conn.enter_passthrough_mode()
      })
    }
    let (response1, _) = @http.get("http://127.0.0.1:\{port}")
    inspect(response1.code, content="200")
    @async.sleep(400)
    let (response2, _) = @http.get("http://127.0.0.1:\{port}")
    inspect(response2.code, content="200")
  }
}
