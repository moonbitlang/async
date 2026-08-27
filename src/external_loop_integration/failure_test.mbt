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
struct ExtLoopWithError {}

///|
impl @external_loop_integration.ExternalEventLoop for ExtLoopWithError with fn poll(
  _self,
  timeout?,
) {
  if timeout is None {
    raise Failure("host event loop died")
  }
}

///|
impl @external_loop_integration.ExternalEventLoop for ExtLoopWithError with fn get_wakeup_callback_for_foreign_thread(
  _,
) {
  () => ()
}

///|
impl @external_loop_integration.ExternalEventLoop for ExtLoopWithError with fn terminate(
  _,
) {
  ()
}

///|
test "failure inside event loop" {
  let log = []
  let extloop = ExtLoopWithError::{  }
  @async.set_external_event_loop(extloop)
  let err = @test.expect_error <| () => {
    @event_loop.with_event_loop <| () => {
      defer log.push("end of main task")
      let (r, w) = @pipe.pipe()
      defer w.close()
      let n = @async.with_task_group() <| _ => {
        defer r.close()
        r.read_all().text()
      }
      log.push("received: \{n}")
    }
  }
  debug_inspect(
    err,
    content=(
      #|Failure("host event loop died")
    ),
  )
  json_inspect(log, content=["end of main task"])
}
