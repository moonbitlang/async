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
extern "C" fn Job::sleep(time : Int) -> Job = "moonbitlang_async_make_sleep_job"

///|
#cfg(target="native")
async fn perform_sleep_job(t : Int) -> Unit {
  let job = Job::sleep(t)
  defer job.free()
  perform_job_in_worker(job, context="") |> ignore
}

///|
#cfg(target="js")
async fn perform_sleep_job(t : Int) -> Unit {
  @async.protect_from_cancel(() => @async.sleep(t))
}

///|
async test "worker basic" {
  let log = StringBuilder::new()
  @async.with_task_group() <| root => {
    root.spawn_bg() <| () => {
      for _ in 0..<3 {
        @async.sleep(400)
        log <+ "tick\n"
      }
    }
    perform_sleep_job(1000)
    log <+ "done\n"
  }
  inspect(
    log.to_string(),
    content=(
      #|tick
      #|tick
      #|done
      #|tick
      #|
    ),
  )
}

///|
async test "worker multiple" {
  let log = StringBuilder::new()
  @async.with_task_group() <| root => {
    root.spawn_bg() <| () => {
      for _ in 0..<3 {
        @async.sleep(200)
        log <+ "tick\n"
      }
    }
    for i in 0..<3 {
      root.spawn_bg() <| () => {
        perform_sleep_job(100 + i * 200)
        log.write_string("#\{i} done\n")
      }
    }
  }
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
async test "worker cancel1" {
  let log = StringBuilder::new()
  @async.with_task_group() <| root => {
    root.spawn_bg() <| () => {
      for _ in 0..<4 {
        @async.sleep(200)
        log <+ "tick\n"
      }
    }
    let task = root.spawn(() => {
      try perform_sleep_job(1000) catch {
        err => {
          log.write_string("sleep cancelled with \{err}\n")
          raise err
        }
      } noraise {
        _ => log <+ "done\n"
      }
    })
    @async.sleep(500)
    log <+ "trying to cancel\n"
    task.cancel()
  }
  inspect(
    log.to_string(),
    content=(
      #|tick
      #|tick
      #|trying to cancel
      #|tick
      #|tick
      #|done
      #|
    ),
  )
}

///|
async test "worker cancel2" {
  let log = StringBuilder::new()
  @async.with_task_group() <| root => {
    root.spawn_bg() <| () => {
      for _ in 0..<3 {
        @async.sleep(400)
        log <+ "tick\n"
      }
    }
    root.spawn_bg(allow_failure=true) <| () => {
      try perform_sleep_job(1000) catch {
        err => {
          log.write_string("sleep cancelled with \{err}\n")
          raise err
        }
      } noraise {
        _ => log <+ "done\n"
      }
    }
    @async.sleep(600)
    log <+ "trying to terminate now\n"
    root.return_immediately(())
  }
  inspect(
    log.to_string(),
    content=(
      #|tick
      #|trying to terminate now
      #|done
      #|
    ),
  )
}

///|
#cfg(any(target="native", target="wasm"))
test "max worker limit" {
  let log = []
  with_event_loop(max_worker_count=2, () => {
    @async.with_task_group <| group => {
      let start = @async.now()
      for i in 0..<4 {
        group.spawn_bg() <| () => {
          let t = (@async.now() - start).to_int() / 200
          log.push("job #\{i} starting at tick #\{t}")
          perform_sleep_job(200)
          let t = (@async.now() - start).to_int() / 200
          log.push("job #\{i} completed at tick #\{t}")
        }
        @async.sleep(50)
      }
    }
  })
  json_inspect(log, content=[
    "job #0 starting at tick #0", "job #1 starting at tick #0", "job #2 starting at tick #0",
    "job #3 starting at tick #0", "job #0 completed at tick #1", "job #1 completed at tick #1",
    "job #2 completed at tick #2", "job #3 completed at tick #2",
  ])
}

///|
#cfg(any(target="native", target="wasm"))
test "cancel queued job" {
  let log = []
  with_event_loop(max_worker_count=1, () => {
    @async.with_task_group <| group => {
      let start = @async.now()
      fn tick() {
        (@async.now() - start + 50).to_int() / 100
      }
      group.spawn_bg() <| () => {
        log.push("main job starting at tick #\{tick()}")
        perform_sleep_job(300)
        log.push("main job completed at tick #\{tick()}")
      }
      @async.sleep(100)
      log.push("queued job starting at tick #\{tick()}")
      // The job here is not cancellable once it start running.
      // But all jobs are cancellable while they are queued.
      try @async.with_timeout(100, () => perform_sleep_job(200)) catch {
        _ => log.push("queued job cancelled at tick #\{tick()}")
      } noraise {
        _ => log.push("queued job completed at tick #\{tick()}")
      }
    }
  })
  json_inspect(log, content=[
    "main job starting at tick #0", "queued job starting at tick #1", "queued job cancelled at tick #2",
    "main job completed at tick #3",
  ])
}
