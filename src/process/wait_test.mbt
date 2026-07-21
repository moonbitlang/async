///|
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
async test "basic wait" {
  let log = StringBuilder::new()
  let test_prog = sleep_prog.wait()
  @async.with_task_group() <| root => {
    root.spawn_bg() <| () => {
      for i in 0..<2 {
        @async.sleep(750)
        log.write_string("\{(i + 1) * 750}ms tick\n")
      }
    }
    @async.sleep(10)
    let result = @process.run(test_prog, ["750"])
    log.write_string("process completed with \{result}\n")
  }
  inspect(
    log.to_string(),
    content=(
      #|750ms tick
      #|process completed with 0
      #|1500ms tick
      #|
    ),
  )
}

///|
async test "wait exitcode" {
  inspect(@process.run(shell, ["-c", "exit 42"]), content="42")
}

///|
async test "wait_pid" {
  let log = StringBuilder::new()
  let test_prog = sleep_prog.wait()
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      for _ in 0..<2 {
        @async.sleep(800)
        log <+ "tick\n"
      }
    }
    let pid = @process.spawn_orphan(test_prog, ["1000", "-exit-code", "42"])
    log.write_string("process terminated with \{@process.wait_pid(pid)}\n")
  }
  inspect(
    log.to_string(),
    content=(
      #|tick
      #|process terminated with 42
      #|tick
      #|
    ),
  )
}

///|
async test "wait exitcode STILL_ACTIVE" {
  guard @event_loop.platform is Windows else {  }
  // `259` is the special value for `STILL_ACTIVE`,
  // wihch is returned by `GetExitCodeProcess` when the process is still running on Windows.
  // However, 259 can also be a valid exit code,
  // so we should not use it to determine whether the process has exited or not.
  inspect(
    @process.run(shell, ["-c", "exit 259"]),
    content=(
      #|259
    ),
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "signal exit code" {
  let sleep = sleep_prog.wait()
  let exit_code = @async.with_task_group <| group => {
    let proc = @process.spawn(group, sleep, ["1000", "-use-default-handler"])
    group.spawn_bg(no_wait=true) <| () => {
      @async.sleep(100)
      @process.graceful_cancel(timeout=1000, signal=SIGINT)(proc.pid)
    }
    proc.wait()
  }
  assert_eq(exit_code, -@signal.SIGINT.to_int())
}
