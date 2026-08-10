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
/// A readiness event can be captured by the async waiting thread while the
/// reader is still draining the pipe. By the time the external loop delivers
/// that event to a newly armed waiter, the pipe may already be empty and the
/// next non-blocking read legitimately returns EAGAIN.
///
/// `/bin/sh` is a real child process whose stdout is connected through
/// `@process.read_from_process()`. This matches the descriptor ownership used
/// by applications that consume a subprocess's stdout through the async loop.
#cfg(all(target="native", not(platform="windows")))
test "external loop retries stale pipe readiness" {
  let main_loop = @external_loop_test.MainLoop()
  @event_loop.with_event_loop <| () => {
    @async.set_external_event_loop(main_loop)
    let round_count = 8
    let burst_count = 256
    let burst_size = 16 * 1024
    let burst = String::make(burst_size, 'x')
    let writer_script =
      #|i=0
      #|while [ "$i" -lt "$2" ]; do
      #|  printf '%s' "$1"
      #|  sleep 0.00005
      #|  i=$((i + 1))
      #|done
      #|
    let expected = burst_count * burst_size
    let buffer = FixedArray::make(4096, b'\x00')
    @async.with_task_group() <| group => {
      for round in 0..<round_count {
        let (reader, writer) = @process.read_from_process()
        defer reader.close()
        let child = @process.spawn(
          group,
          "/bin/sh",
          ["-c", writer_script, "burst-writer", burst, burst_count.to_string()],
          stdout=writer,
        )
        for received = 0; received < expected; {
          let n = reader.read(buffer, offset=0, max_len=buffer.length())
          if n == 0 {
            fail(
              "round \{round} reached EOF after \{received} of \{expected} bytes",
            )
          }
          continue received + n
        } nobreak {
          assert_eq(received, expected)
        }
        assert_eq(child.wait(), 0)
      }
    }
  }
}
