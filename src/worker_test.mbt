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
test "worker basic" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    root.spawn_bg(fn() {
      for _ in 0..<4 {
        @async.sleep(20)
        log.write_string("tick\n")
      }
    })
    guard @event_loop.perform_job(Sleep(100)) == 0
    log.write_string("done\n")
  })
  inspect(
    log.to_string(),
    content=(
      #|tick
      #|tick
      #|tick
      #|tick
      #|done
      #|
    ),
  )
}

///|
test "worker multiple" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    root.spawn_bg(fn() {
      for _ in 0..<3 {
        @async.sleep(40)
        log.write_string("tick\n")
      }
    })
    for i in 0..<3 {
      root.spawn_bg(fn() {
        @event_loop.perform_job(Sleep(20 + i * 40)) |> ignore
        log.write_string("#\{i} done\n")
      })
    }
  })
  inspect(
    log.to_string(),
    content=(
      #|#0 done
      #|tick
      #|#1 done
      #|tick
      #|#2 done
      #|tick
      #|
    ),
  )
}

///|
test "worker cancel1" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    root.spawn_bg(fn() {
      for _ in 0..<4 {
        @async.sleep(20)
        log.write_string("tick\n")
      }
    })
    let task = root.spawn(allow_failure=true, fn() {
      try @event_loop.perform_job(Sleep(100)) catch {
        err => {
          log.write_string("sleep cancelled with \{err}\n")
          raise err
        }
      } noraise {
        _ => log.write_string("done\n")
      }
    })
    @async.sleep(50)
    log.write_string("trying to cancel\n")
    task.cancel()
  })
  inspect(
    log.to_string(),
    content=(
      #|tick
      #|tick
      #|trying to cancel
      #|tick
      #|tick
      #|sleep cancelled with Cancelled
      #|
    ),
  )
}

///|
test "worker cancel2" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    root.spawn_bg(fn() {
      for _ in 0..<3 {
        @async.sleep(40)
        log.write_string("tick\n")
      }
    })
    root.spawn_bg(allow_failure=true, fn() {
      try @event_loop.perform_job(Sleep(100)) catch {
        err => {
          log.write_string("sleep cancelled with \{err}\n")
          raise err
        }
      } noraise {
        _ => log.write_string("done\n")
      }
    })
    @async.sleep(60)
    log.write_string("trying to terminate now\n")
    root.return_immediately(())
  })
  inspect(
    log.to_string(),
    content=(
      #|tick
      #|trying to terminate now
      #|sleep cancelled with Cancelled
      #|
    ),
  )
}
