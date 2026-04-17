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
fn make_test_prog(name : String) -> @async.Lazy[String] {
  @async.Lazy(() => {
    let code = @process.run("moon", [
      "build",
      "--manifest-path",
      "src/process/test_programs/moon.mod.json",
      "src/process/test_programs/\{name}",
      "--debug",
    ])
    if code != 0 {
      fail("failed to build test program `\{name}`: \{code}")
    }
    "src/process/test_programs/_build/native/debug/build/\{name}/\{name}.exe"
  })
}

///|
let sleep_prog : @async.Lazy[String] = make_test_prog("sleep")

///|
async test "cancel with default signal" {
  let test_prog = sleep_prog.wait()
  let log = []
  @async.with_task_group(group => {
    let (r, w) = @process.read_from_process()
    let task = group.spawn(() => {
      defer log.push("process terminates")
      @process.run(test_prog, stdout=w, [
        "10000", "-use-default-handler", "-print-after-sleep", "normal exit", "-print-finally",
        "before exit",
      ])
    })
    group.spawn_bg(() => {
      defer r.close()
      while r.read_some() is Some(data) {
        let data = @utf8.decode(data).replace_all(old="\r\n", new="\n").trim()
        log.push("from process: \{data}")
      }
    })
    @async.sleep(500)
    task.cancel()
    log.push("cancelling task running process")
  })
  json_inspect(log, content=[
    "cancelling task running process", "from process: before exit", "process terminates",
  ])
}

///|
// On Windows, `CTRL_C_EVENT` cannot be sent to a single process
#cfg(not(platform="windows"))
async test "cancel with ctrl+c" {
  let test_prog = sleep_prog.wait()
  let log = []
  @async.with_task_group(group => {
    let (r, w) = @process.read_from_process()
    let task = group.spawn(() => {
      defer log.push("process terminates")
      let cancel_handler = @process.graceful_cancel(
        timeout=5000,
        signal=@signal.SIGINT,
      )
      @process.run(test_prog, stdout=w, cancel_handler~, [
        "10000", "-use-default-handler", "-print-after-sleep", "normal exit", "-print-finally",
        "before exit",
      ])
    })
    group.spawn_bg(() => {
      defer r.close()
      while r.read_some() is Some(data) {
        let data = @utf8.decode(data).replace_all(old="\r\n", new="\n").trim()
        log.push("from process: \{data}")
      }
    })
    @async.sleep(500)
    task.cancel()
    log.push("cancelling task running process")
  })
  json_inspect(log, content=[
    "cancelling task running process", "from process: before exit", "process terminates",
  ])
}

///|
// On Windows, `CTRL_CLOSE_EVENT` cannot be sent programmatically
#cfg(not(platform="windows"))
async test "cancel with SIGHUP" {
  let test_prog = sleep_prog.wait()
  let log = []
  @async.with_task_group(group => {
    let (r, w) = @process.read_from_process()
    let task = group.spawn(() => {
      defer log.push("process terminates")
      let cancel_handler = @process.graceful_cancel(
        timeout=5000,
        signal=@signal.SIGHUP,
      )
      @process.run(test_prog, stdout=w, cancel_handler~, [
        "10000", "-use-default-handler", "-print-after-sleep", "normal exit", "-print-finally",
        "before exit",
      ])
    })
    group.spawn_bg(() => {
      defer r.close()
      while r.read_some() is Some(data) {
        let data = @utf8.decode(data).replace_all(old="\r\n", new="\n").trim()
        log.push("from process: \{data}")
      }
    })
    @async.sleep(500)
    task.cancel()
    log.push("cancelling task running process")
  })
  json_inspect(log, content=[
    "cancelling task running process", "from process: before exit", "process terminates",
  ])
}
