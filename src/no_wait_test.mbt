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
test "no_wait cancelled" {
  let buf = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    root.spawn_bg(no_wait=true, fn() {
      try @async.sleep(1000) catch {
        err => {
          buf.write_string("`no_wait` task cancelled with \{err}\n")
          raise err
        }
      } noraise {
        _ => buf.write_string("`no_wait` task finished successfully\n")
      }
    })
    @async.sleep(100)
    buf.write_string("main task terminate\n")
  })
  inspect(
    buf.to_string(),
    content=(
      #|main task terminate
      #|`no_wait` task cancelled with Cancelled
      #|
    ),
  )
}

///|
test "no_wait normal exit" {
  let buf = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    root.spawn_bg(no_wait=true, fn() {
      try @async.sleep(100) catch {
        err => {
          buf.write_string("`no_wait` task cancelled with \{err}\n")
          raise err
        }
      } noraise {
        _ => buf.write_string("`no_wait` task finished successfully\n")
      }
    })
    @async.sleep(200)
    buf.write_string("main task terminate\n")
  })
  inspect(
    buf.to_string(),
    content=(
      #|`no_wait` task finished successfully
      #|main task terminate
      #|
    ),
  )
}
