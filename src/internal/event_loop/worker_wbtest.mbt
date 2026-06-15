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
extern "C" fn NativeJob::sleep(time : Int) -> NativeJob = "moonbitlang_async_make_sleep_job"

///|
#cfg(target="native")
async fn perform_sleep_job(t : Int) -> Unit {
  @coroutine.check_cancellation()
  guard curr_loop.val is Some(evloop)
  let (subscription_id, operation) = evloop.subscribe_backend_operation(
    subscription_id => {
      evloop.backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::sleep(t),
      )
    },
    Wake(@coroutine.current_coroutine()),
  )
  try {
    evloop.wait_for_submitted_operation(subscription_id, operation)
    if operation.err() is err && err > 0 {
      raise @os_error.OSError(err, context="")
    }
  } catch {
    err => {
      operation.free()
      raise err
    }
  } noraise {
    _ => operation.free()
  }
}

///|
#cfg(target="js")
async fn perform_sleep_job(t : Int) -> Unit {
  @async.protect_from_cancel(() => @async.sleep(t), resume_on_cancel=true)
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
#cfg(target="native")
async test "queued worker cancellation removes job" {
  guard curr_loop.val is Some(evloop)
  let first : Job = {
    id: evloop.backend.next_operation_id(),
    native: NativeJob::sleep(1),
  }
  let second : Job = {
    id: evloop.backend.next_operation_id(),
    native: NativeJob::sleep(1),
  }
  defer first.free()
  defer second.free()
  evloop.backend.thread_pool.job_queue.push_back(first)
  evloop.backend.thread_pool.job_queue.push_back(second)
  assert_true(evloop.backend.thread_pool.remove_queued_job(first.id()))
  assert_false(evloop.backend.thread_pool.remove_queued_job(first.id()))
  guard evloop.backend.thread_pool.job_queue.pop_front() is Some(job) else {
    abort("remaining queued job was removed")
  }
  assert_true(job.id() == second.id())
  assert_true(evloop.backend.thread_pool.job_queue.pop_front() is None)
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
