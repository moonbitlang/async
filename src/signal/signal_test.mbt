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
  Lazy() <| () => {
    let code = @process.run("moon", [
      "build",
      "test_programs/\{name}",
      "--debug",
      "--target-dir",
      "_build/test_programs",
    ])
    if code != 0 {
      fail("failed to build test program `\{name}`: \{code}")
    }
    "./_build/test_programs/native/debug/build/moonbitlang/async_test_programs/\{name}/\{name}.exe"
  }
}

///|
let sleep_prog : @async.Lazy[String] = make_test_prog("sleep")

///|
async test "cancel with default signal" {
  let test_prog = sleep_prog.wait()
  let log = []
  @async.with_task_group() <| group => {
    let (r, w) = @process.read_from_process()
    let task = group.spawn(() => {
      defer log.push("process terminates")
      @process.run(test_prog, stdout=w, [
        "10000", "-use-default-handler", "-print-after-sleep", "normal exit", "-print-finally",
        "before exit",
      ])
    })
    group.spawn_bg() <| () => {
      defer r.close()
      while r.read_some() is Some(data) {
        let data = @utf8.decode(data).replace_all(old="\r\n", new="\n").trim()
        log.push("from process: \{data}")
      }
    }
    @async.sleep(500)
    task.cancel()
    log.push("cancelling task running process")
  }
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
  @async.with_task_group() <| group => {
    let (r, w) = @process.read_from_process()
    let task = group.spawn(() => {
      defer log.push("process terminates")
      let cancel_handler = @process.graceful_cancel(timeout=5000, signal=SIGINT)
      @process.run(test_prog, stdout=w, cancel_handler~, [
        "10000", "-use-default-handler", "-print-after-sleep", "normal exit", "-print-finally",
        "before exit",
      ])
    })
    group.spawn_bg() <| () => {
      defer r.close()
      while r.read_some() is Some(data) {
        let data = @utf8.decode(data).replace_all(old="\r\n", new="\n").trim()
        log.push("from process: \{data}")
      }
    }
    @async.sleep(500)
    task.cancel()
    log.push("cancelling task running process")
  }
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
  @async.with_task_group() <| group => {
    let (r, w) = @process.read_from_process()
    let task = group.spawn(() => {
      defer log.push("process terminates")
      let cancel_handler = @process.graceful_cancel(timeout=5000, signal=SIGHUP)
      @process.run(test_prog, stdout=w, cancel_handler~, [
        "10000", "-use-default-handler", "-print-after-sleep", "normal exit", "-print-finally",
        "before exit",
      ])
    })
    group.spawn_bg() <| () => {
      defer r.close()
      while r.read_some() is Some(data) {
        let data = @utf8.decode(data).replace_all(old="\r\n", new="\n").trim()
        log.push("from process: \{data}")
      }
    }
    @async.sleep(500)
    task.cancel()
    log.push("cancelling task running process")
  }
  json_inspect(log, content=[
    "cancelling task running process", "from process: before exit", "process terminates",
  ])
}

///|
async test "change cancellation signal set in the middle #1" {
  let test_prog = sleep_prog.wait()
  let log = []
  @async.with_task_group() <| group => {
    let (r1, w1) = @process.write_to_process()
    defer w1.close()
    let (r2, w2) = @process.read_from_process()
    group.spawn_bg() <| () => {
      defer r2.close()
      while r2.read_some() is Some(data) {
        let data = @utf8.decode(data).replace_all(old="\r\n", new="\n").trim()
        log.push("from process: \{data}")
      }
    }
    let proc = @process.spawn(group, test_prog, stdin=r1, stdout=w2, [
      "2000", "-wait-on-init", "-print-finally", "before exit", "-swallow-cancel-signal",
    ])
    @async.sleep(250)
    proc.cancel()
    log.push("cancelling task running process")
    @async.sleep(250)
  }
  json_inspect(log, content=[
    "cancelling task running process", "from process: before exit",
  ])
}

///|
async test "change cancellation signal set in the middle #2" {
  let test_prog = sleep_prog.wait()
  let log = []
  @async.with_task_group() <| group => {
    let (r1, w1) = @process.write_to_process()
    defer w1.close()
    let (r2, w2) = @process.read_from_process()
    group.spawn_bg() <| () => {
      defer r2.close()
      while r2.read_some() is Some(data) {
        let data = @utf8.decode(data).replace_all(old="\r\n", new="\n").trim()
        log.push("from process: \{data}")
      }
    }
    let proc = @process.spawn(group, test_prog, stdin=r1, stdout=w2, [
      "500", "-wait-on-init", "-print-finally", "before exit", "-swallow-cancel-signal",
    ])
    w1.write("whatever")
    @async.sleep(250)
    proc.cancel()
    log.push("cancelling task running process")
  }
  json_inspect(log, content=[
    "cancelling task running process", "from process: received termination signal",
  ])
}
