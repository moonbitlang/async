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
async test "spawn_in_group wait" {
  let log = []
  let sleep = sleep_prog.wait()
  @async.with_task_group <| outer => {
    @async.with_task_group <| inner => {
      let (r, w) = @process.read_from_process()
      let _ = @process.spawn(inner, sleep, stdout=w, [
        "500", "-print-after-sleep", "done",
      ])
      outer.spawn_bg() <| () => {
        defer r.close()
        log.push("from process: \{r.read_all().text().trim()}")
      }
      log.push("main task completed")
    }
    log.push("`with_task_group` completed")
  }
  json_inspect(log, content=[
    "main task completed", "from process: done", "`with_task_group` completed",
  ])
}

///|
async test "spawn_in_group cancel" {
  let sleep = sleep_prog.wait()
  @async.with_task_group() <| outer => {
    let (r, w) = @process.read_from_process()
    outer.spawn_bg() <| () => {
      defer r.close()
      inspect(r.read_all().text().trim(), content="received termination signal")
    }
    @async.with_task_group() <| inner => {
      let _ = @process.spawn(inner, sleep, ["10000"], stdout=w, no_wait=true)
      @async.sleep(300)
    }
  }
}

///|
async test "Process::wait" {
  let sleep = sleep_prog.wait()
  @async.with_task_group() <| group => {
    let (r, w) = @process.read_from_process()
    let child = @process.spawn(group, sleep, stdout=w, [
      "500", "-exit-code", "42", "-print-after-sleep", "done",
    ])
    let output = group.spawn() <| () => {
      defer r.close()
      r.read_all().text().trim().to_owned()
    }
    let result = child.wait()
    debug_inspect(
      output.try_wait(),
      content=(
        #|Some("done")
      ),
    )
    inspect(result, content="42")
    // `.wait()` should be idempotent
    inspect(child.wait(), content="42")
  }
}

///|
async test "Process::try_wait" {
  let sleep = sleep_prog.wait()
  @async.with_task_group() <| group => {
    let (r, w) = @process.read_from_process()
    let child = @process.spawn(group, sleep, stdout=w, [
      "500", "-exit-code", "42", "-print-after-sleep", "end",
    ])
    let output = group.spawn() <| () => {
      defer r.close()
      r.read_all().text().trim().to_owned()
    }
    debug_inspect(child.try_wait(), content="None")
    inspect(output.wait(), content="end")
    // give some time for the child process to cleanup itself
    @async.sleep(200)
    debug_inspect(child.try_wait(), content="Some(42)")
  }
}

///|
async test "Process::cancel" {
  let sleep = sleep_prog.wait()
  let t0 = @async.now()
  @async.with_task_group() <| group => {
    let (r, w) = @process.read_from_process()
    let child = @process.spawn(group, sleep, stdout=w, ["10000"])
    group.spawn_bg() <| () => {
      defer r.close()
      inspect(r.read_all().text().trim(), content="received termination signal")
    }
    @async.sleep(500)
    child.cancel()
  }
  assert_true(@async.now() - t0 < 10000)
}
