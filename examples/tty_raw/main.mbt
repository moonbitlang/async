// Copyright 2026 International Digital Economy Academy
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
async fn main {
  let tty = @tty.open()
  let saved = tty.get_state()
  tty.set_state(saved.make_raw())
  defer tty.set_state(saved)
  @async.with_task_group(async fn(group) {
    group.add_defer(() => {
      @async.protect_from_cancel(async fn() {
        @async.with_timeout(1000, async fn() {
          tty.write(b"\x1b[?1004l\x1b[?1003l\x1b[?1006l")
        })
      })
    })
    // Focus reporting, all mouse movement, and SGR mouse encoding.
    tty.write(b"\x1b[?1004h\x1b[?1003h\x1b[?1006h")
    let (rows, cols) = tty.size()
    tty.write(
      "Raw mode: type keys, move/click the mouse, change focus, or resize. Ctrl+C exits.\r\n",
    )
    tty.write("Size: \{rows} rows x \{cols} columns\r\n")
    while tty.read_event() is Some(event) {
      match event {
        Input(bytes) => {
          let values = bytes
            .iter()
            .map(byte => {
              if byte < 0x80 {
                "\{@debug.Repr(byte)} (\{@debug.Repr(byte.to_char())})"
              } else {
                "\{@debug.Repr(byte)}"
              }
            })
            .to_array()
            .join(", ")
          tty.write("Input: [\{values}]\r\n")
          if bytes.iter().any(byte => byte == b'\x03') {
            tty.write("Leaving raw mode.\r\n")
            break
          }
        }
        Resize => {
          let (rows, cols) = tty.size()
          tty.write("Resize: \{rows} rows x \{cols} columns\r\n")
        }
      }
    }
  })
}
