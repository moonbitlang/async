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
#cfg(platform="windows")
extern "C" fn console_open(rows : Int32, cols : Int32) -> Int32 = "moonbitlang_async_tty_test_console_open"

///|
#cfg(platform="windows")
extern "C" fn console_close() = "moonbitlang_async_tty_test_console_close"

///|
#cfg(platform="windows")
#borrow(data)
extern "C" fn console_input_ffi(data : Bytes) -> Int32 = "moonbitlang_async_tty_test_console_input"

///|
#cfg(platform="windows")
extern "C" fn console_resize(rows : Int32, cols : Int32) -> Int32 = "moonbitlang_async_tty_test_console_resize"

///|
/// Send `data` to the pseudo console as if typed in the terminal.
#cfg(platform="windows")
fn console_input(data : Bytes) -> Unit raise {
  guard console_input_ffi(data) == 0 else { fail("cannot write console input") }
}

///|
#cfg(platform="windows")
let console_lock : @async.Mutex = @async.Mutex()

///|
/// Run `f` with a `Tty` on a fresh 24x80 pseudo console,
/// driven through `console_input` and `console_resize`.
///
/// The process is attached to the pseudo console for the duration of `f`.
/// There is one console per process, so `console_lock` keeps these tests
/// from overlapping.
#cfg(platform="windows")
async fn with_console(f : async (Tty) -> Unit) -> Unit {
  console_lock.acquire()
  defer console_lock.release()
  guard console_open(24, 80) == 0 else { fail("cannot open pseudo console") }
  defer console_close()
  let tty = Tty::open_path(b"", context="with_console")
  defer {
    tty.leave_raw_mode() catch {
      _ => ()
    }
    tty.detach()
  }
  f(tty)
}

///|
#cfg(platform="windows")
async test "console: raw mode delivers VT bytes" {
  with_console(tty => {
    tty.enter_raw_mode()
    console_input(b"abc")
    assert_eq(tty.read_exactly(3), b"abc")
    // special keys arrive as VT sequences, Ctrl-C as a plain byte
    console_input(b"\x1b[A\x03")
    assert_eq(tty.read_exactly(4), b"\x1b[A\x03")
    // non-ASCII text, including a character outside the BMP
    console_input(b"\xc3\xa9\xe4\xb8\xad\xf0\x9f\x98\x80")
    assert_eq(tty.read_exactly(9), b"\xc3\xa9\xe4\xb8\xad\xf0\x9f\x98\x80")
  })
}

///|
#cfg(platform="windows")
async test "console: cooked mode delivers whole lines" {
  with_console(tty => {
    console_input(b"abc\r")
    assert_eq(tty.read_exactly(5), b"abc\r\n")
    // a partial line is held back, and the parked read can be cancelled
    console_input(b"xyz")
    assert_true(@async.with_timeout_opt(100, () => tty.read_event()) is None)
  })
}

///|
#cfg(platform="windows")
async test "console: raw mode is idempotent and restores the console" {
  with_console(tty => {
    tty.enter_raw_mode()
    tty.enter_raw_mode()
    console_input(b"q")
    assert_eq(tty.read_exactly(1), b"q")
    tty.leave_raw_mode()
    tty.leave_raw_mode()
    // back in cooked mode: a partial line is held back again
    console_input(b"w")
    assert_true(@async.with_timeout_opt(100, () => tty.read_event()) is None)
  })
}

///|
#cfg(platform="windows")
async test "console: size and resize" {
  with_console(tty => {
    debug_inspect(tty.size(), content="(24, 80)")
    tty.enter_raw_mode()
    let event = @async.with_task_group(group => {
      group.spawn_bg(() => {
        @async.sleep(50)
        guard console_resize(30, 100) == 0 else { fail("cannot resize") }
      })
      tty.read_event()
    })
    debug_inspect(event, content="Some(Resize)")
    debug_inspect(tty.size(), content="(30, 100)")
    console_input(b"x")
    assert_true(tty.read_event() is Some(Input(b"x")))
  })
}

///|
#cfg(platform="windows")
async test "console: cancelling a parked read keeps the console usable" {
  with_console(tty => {
    tty.enter_raw_mode()
    assert_true(@async.with_timeout_opt(50, () => tty.read_event()) is None)
    console_input(b"z")
    assert_true(tty.read_event() is Some(Input(b"z")))
  })
}

///|
#cfg(platform="windows")
async test "console: writer" {
  with_console(tty => {
    tty.enter_raw_mode()
    tty.write("héllo \u{1F600}\r\n")
  })
}
