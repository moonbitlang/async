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
/// The writer runs outside MoonBit so this test exercises the same ownership
/// boundary as a subprocess stdout pipe without depending on a subprocess or
/// any application code.
#cfg(all(target="native", not(platform="windows")))
test "external loop retries stale pipe readiness" {
  let main_loop = @external_loop_test.MainLoop()
  @event_loop.with_event_loop <| () => {
    @async.set_external_event_loop(main_loop)
    let round_count = 8
    let burst_count = 256
    let burst_size = 16 * 1024
    let expected = burst_count * burst_size
    let buffer = FixedArray::make(4096, b'\x00')
    for round in 0..<round_count {
      let (reader, writer) = @pipe.pipe()
      defer reader.close()
      let started = @external_loop_test.start_pipe_burst_writer(
        writer.fd(),
        burst_count~,
        burst_size~,
        gap_us=50,
      )
      if started < 0 {
        writer.close()
        @os_error.check_errno("start pipe burst writer")
      }
      writer.close()

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
    }
  }
}
