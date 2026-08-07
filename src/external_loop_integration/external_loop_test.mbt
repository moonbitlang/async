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
#cfg(target="native")
test "external loop mixed" {
  let main_loop = @external_loop_test.MainLoop()
  @event_loop.with_event_loop <| () => {
    @async.set_external_event_loop(main_loop)
    @async.with_task_group <| group => {
      let start = @async.now()
      fn tick() {
        (@async.now() - start + 50) / 150
      }
      let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      group.spawn_bg() <| () => {
        defer server.close()
        let (conn, _) = server.accept()
        defer conn.close()
        main_loop.log("TCP server received connection at #\{tick()}")
      }
      group.spawn_bg() <| () => {
        @async.sleep(300)
        main_loop.log("attempting connect")
        let conn = @socket.Tcp::connect(server.addr)
        @async.sleep(100)
        defer conn.close()
      }
      group.spawn_bg(no_wait=true) <| () => {
        for ;; {
          main_loop.wait()
          main_loop.log("received main loop specific event at #\{tick()}")
        }
      }
      group.spawn_bg() <| () => {
        @external_loop_test.trigger_main_loop_event(delay=150)
      }
      group.spawn_bg() <| () => {
        @external_loop_test.trigger_main_loop_event(delay=450)
      }
      @async.sleep(600)
    }
  }
  json_inspect(main_loop.log, content=[
    "main loop: received custom event", "received main loop specific event at #1",
    "attempting connect", "TCP server received connection at #2", "main loop: received custom event",
    "received main loop specific event at #3", "terminate main loop",
  ])
}

///|
#cfg(target="native")
test "external loop blocked on external only" {
  let main_loop = @external_loop_test.MainLoop()
  @event_loop.with_event_loop <| () => {
    @async.set_external_event_loop(main_loop)
    @async.with_task_group <| group => {
      let start = @async.now()
      fn tick() {
        (@async.now() - start + 50) / 150
      }
      group.spawn_bg() <| () => {
        @external_loop_test.trigger_main_loop_event(delay=150)
      }
      main_loop.wait()
      main_loop.log("main loop received custom event at #\{tick()}")
    }
  }
  json_inspect(main_loop.log, content=[
    "main loop: received custom event", "main loop received custom event at #1",
    "terminate main loop",
  ])
}

///|
#cfg(target="native")
test "external loop blocked on async only" {
  let main_loop = @external_loop_test.MainLoop()
  @event_loop.with_event_loop <| () => {
    @async.set_external_event_loop(main_loop)
    @async.with_task_group <| group => {
      let (r, w) = @pipe.pipe()
      defer r.close()
      defer w.close()
      let start = @async.now()
      fn tick() {
        (@async.now() - start + 50) / 150
      }
      for i, delay in [150, 300] {
        group.spawn_bg() <| () => {
          @external_loop_test.trigger_event(w.fd(), i, delay~)
        }
      }
      for _ in 0..<2 {
        guard! r.read_exactly(4) is [i32le(data)]
        main_loop.log("main loop received \{data} at #\{tick()}")
      }
    }
  }
  json_inspect(main_loop.log, content=[
    "main loop received 0 at #1", "main loop received 1 at #2", "terminate main loop",
  ])
}
