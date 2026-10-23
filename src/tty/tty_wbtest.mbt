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
#cfg(not(platform="windows"))
extern "C" fn open_pty() -> @fd_util.Fd = "moonbitlang_async_tty_test_open_pty"

///|
#cfg(not(platform="windows"))
extern "C" fn pty_name(master : @fd_util.Fd) -> Bytes = "moonbitlang_async_tty_test_pty_name"

///|
#cfg(not(platform="windows"))
extern "C" fn set_size(fd : @fd_util.Fd, rows : Int32, cols : Int32) -> Int32 = "moonbitlang_async_tty_test_set_size"

///|
#cfg(not(platform="windows"))
extern "C" fn send_winch() = "moonbitlang_async_tty_test_send_winch"

///|
/// Run `f` with a `Tty` on the slave side of a fresh pseudo terminal,
/// and the master side wrapped as a `RawFd` to play the role of the terminal.
///
/// `SIGWINCH` is process wide, so a resize sent by one test is seen by every
/// terminal handle. `moon.pkg` therefore sets `max_concurrent_tests = 1`:
/// tests that rely on a read staying parked must not overlap with tests
/// that send resizes.
#cfg(not(platform="windows"))
async fn with_pty(f : async (Tty, @raw_fd.RawFd) -> Unit) -> Unit {
  let master_fd = open_pty()
  guard @fd_util.fd_is_valid(master_fd) else { fail("cannot open pty") }
  let master = @raw_fd.RawFd(master_fd)
  defer master.close()
  let tty = Tty::open_path(pty_name(master_fd), context="with_pty")
  defer {
    tty.leave_raw_mode() catch {
      _ => ()
    }
    tty.detach()
  }
  f(tty, master)
}

///|
#cfg(not(platform="windows"))
async fn read_master(master : @raw_fd.RawFd) -> Bytes {
  let buf = FixedArray::make(64, b'\x00')
  let n = master.read(buf)
  Bytes::from_array(buf[:n])
}

///|
#cfg(not(platform="windows"))
async test "cooked mode delivers whole lines" {
  with_pty((tty, master) => {
    ignore(master.write(b"abc\n"))
    assert_true(tty.read_event() is Some(Input(b"abc\n")))
    // a partial line is held back by the line discipline
    ignore(master.write(b"xyz"))
    assert_true(@async.with_timeout_opt(100, () => tty.read_event()) is None)
  })
}

///|
#cfg(not(platform="windows"))
async test "raw mode is idempotent and restores the terminal" {
  with_pty((tty, master) => {
    tty.enter_raw_mode()
    tty.enter_raw_mode()
    ignore(master.write(b"\x1b[A"))
    assert_true(tty.read_event() is Some(Input(b"\x1b[A")))
    tty.leave_raw_mode()
    tty.leave_raw_mode()
    // back in cooked mode: a partial line is held back again
    ignore(master.write(b"q"))
    assert_true(@async.with_timeout_opt(100, () => tty.read_event()) is None)
    ignore(master.write(b"\n"))
    assert_true(tty.read_event() is Some(Input(b"q\n")))
  })
}

///|
#cfg(not(platform="windows"))
async test "size" {
  with_pty((tty, master) => {
    assert_true(set_size(master.fd, 24, 80) == 0)
    debug_inspect(tty.size(), content="(24, 80)")
    assert_true(set_size(master.fd, 50, 132) == 0)
    debug_inspect(tty.size(), content="(50, 132)")
  })
}

///|
#cfg(not(platform="windows"))
async test "resize interrupts a parked read" {
  with_pty((tty, master) => {
    tty.enter_raw_mode()
    let event = @async.with_task_group(group => {
      group.spawn_bg(() => {
        @async.sleep(50)
        send_winch()
      })
      tty.read_event()
    })
    debug_inspect(event, content="Some(Resize)")
    ignore(master.write(b"x"))
    assert_true(tty.read_event() is Some(Input(b"x")))
  })
}

///|
#cfg(not(platform="windows"))
async test "resize while idle is reported once" {
  with_pty((tty, master) => {
    tty.enter_raw_mode()
    send_winch()
    send_winch()
    send_winch()
    debug_inspect(tty.read_event(), content="Some(Resize)")
    ignore(master.write(b"y"))
    assert_true(tty.read_event() is Some(Input(b"y")))
  })
}

///|
#cfg(not(platform="windows"))
async test "cancelling a parked read keeps the terminal usable" {
  with_pty((tty, master) => {
    tty.enter_raw_mode()
    assert_true(@async.with_timeout_opt(50, () => tty.read_event()) is None)
    ignore(master.write(b"z"))
    assert_true(tty.read_event() is Some(Input(b"z")))
  })
}

///|
#cfg(not(platform="windows"))
async test "concurrent reads are rejected" {
  with_pty((tty, _master) => {
    tty.enter_raw_mode()
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => ignore(tty.read_event()))
      @async.sleep(20)
      let err = @test_util.expect_error_async(() => tty.read_event())
      assert_true(err is ReadInProgress)
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "reader and writer" {
  with_pty((tty, master) => {
    tty.enter_raw_mode()
    ignore(master.write(b"hello"))
    assert_eq(tty.read_exactly(5), b"hello")
    tty.write(b"out")
    assert_eq(read_master(master), b"out")
    // a resize seen by a plain read is reported by the next `read_event`
    ignore(master.write(b"world"))
    send_winch()
    assert_eq(tty.read_exactly(5), b"world")
    debug_inspect(tty.read_event(), content="Some(Resize)")
  })
}
