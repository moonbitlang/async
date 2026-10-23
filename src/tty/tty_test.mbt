///|
fn make_test_prog(name : String) -> @async.Lazy[String] {
  Lazy() <| () => {
    let code = @process.run("moon", [
      "build",
      "test_programs/\{name}",
      "--debug",
      "--target",
      "native",
      "--target-dir",
      "_build/test_programs",
    ])
    if code != 0 {
      fail("failed to build test program `\{name}`: \{code}")
    }
    "./_build/test_programs/native/debug/build/moonbitlang/async_test_programs/\{name}/\{name}.exe"
  }
}

///|
let ttyd : @async.Lazy[String] = make_test_prog("ttyd")

///|
let pty : @async.Lazy[String] = make_test_prog("pty")

///|
/// See `test_programs/ttyd`.
priv struct Ttyd {
  input : @process.WriteToProcess
  output : @process.ReadFromProcess
  control : @process.ReadFromProcess
  rpc : @socket.Tcp
  mut next_id : Int32
}

///|
async fn Ttyd::call(self : Ttyd, name : String, params~ : Json) -> Json {
  let id = self.next_id
  self.next_id += 1
  let request : Json = {
    "jsonrpc": "2.0",
    "id": id,
    "method": name,
    "params": params,
  }
  self.rpc.write("\{request.stringify()}\n")
  guard self.rpc.read_until("\n") is Some(line) else {
    fail("ttyd closed the connection")
  }
  match @json.parse(line) {
    { "id": Number(response_id, ..), "result": result, .. } if response_id ==
      id.to_double() => result
    response => fail("`\{name}` failed: \{response.stringify()}")
  }
}

///|
async fn Ttyd::enter_raw_mode(self : Ttyd) -> Unit {
  self.call("enter_raw_mode", params={}) |> ignore()
}

///|
async fn Ttyd::leave_raw_mode(self : Ttyd) -> Unit {
  self.call("leave_raw_mode", params={}) |> ignore()
}

///|
/// `@tty.Tty::size` in `ttyd`.
async fn Ttyd::size(self : Ttyd) -> (Int32, Int32) {
  guard self.call("size", params={}) is [Number(rows, ..), Number(cols, ..)] else {
    fail("unexpected `size` result")
  }
  (rows.to_int(), cols.to_int())
}

///|
/// `@tty.Tty::read_event` in `ttyd`.
///
/// With `timeout`, the read is cancelled inside `ttyd` after `timeout`
/// milliseconds and `Timeout` is raised. The timeout must not be applied
/// here with `@async.with_timeout`: cancelling the call would leave the
/// late response on the connection, to be taken by the next call.
async fn Ttyd::read_event(self : Ttyd, timeout? : Int32) -> @tty.Event? {
  let params : Json = if timeout is Some(timeout) {
    { "timeout": timeout }
  } else {
    {}
  }
  let result = self.call("read_event", params~)
  match result {
    { "type": "input", "bytes": String(bytes), .. } =>
      Some(Input(@base64.decode(bytes)))
    { "type": "resize", .. } => Some(Resize)
    { "type": "eof", .. } => None
    { "type": "timeout", .. } => raise Timeout
    _ => fail("unexpected `read_event` result: \{result.stringify()}")
  }
}

///|
/// Raised by `Ttyd::read_event` when its `timeout` expires.
priv suberror Timeout derive(Debug)

///|
/// `@io.Reader::read_exactly` on the `@tty.Tty` in `ttyd`.
async fn Ttyd::read_exactly(self : Ttyd, len : Int32) -> Bytes {
  guard self.call("read_exactly", params={ "len": len }) is String(bytes) else {
    fail("unexpected `read_exactly` result")
  }
  @base64.decode(bytes)
}

///|
/// `@io.Writer::write` on the `@tty.Tty` in `ttyd`.
async fn Ttyd::write(self : Ttyd, bytes : Bytes) -> Unit {
  self.call("write", params={ "bytes": @base64.encode(bytes) }) |> ignore
}

///|
/// Input is framed so it can share the harness pipe with control commands
/// without interpreting any of the terminal input bytes.
async fn Ttyd::send_input(self : Ttyd, bytes : Bytes) -> Unit {
  self.input.write("input \{bytes.length()}\n")
  self.input.write(bytes)
}

///|
async fn Ttyd::is_canonical(self : Ttyd) -> Bool {
  @async.with_task_group(group => {
    self.send_input(b"x")
    let reading = group.spawn(() => self.read_event())
    @async.sleep(200)
    if reading.try_wait() is Some(event) {
      assert_eq(event, Some(Input(b"x")))
      false
    } else {
      // Finish the same read instead of cancelling a partially entered line.
      let (enter, line) = if @async.platform is Windows {
        (b"\r", b"x\r\n")
      } else {
        (b"\n", b"x\n")
      }
      self.send_input(enter)
      assert_eq(reading.wait(), Some(Input(line)))
      true
    }
  })
}

///|
async fn Ttyd::resize(self : Ttyd, rows : Int32, cols : Int32) -> Unit {
  self.input.write("resize \{rows} \{cols}\n")
  assert_eq(self.control.read_until("\n"), Some("ok"))
}

///|
/// ConPTY emits screen initialization and cursor controls. Discard output until
/// quiet before testing whether new input echoes; do not mistake setup for echo.
async fn Ttyd::drain_output(self : Ttyd) -> Unit {
  while @async.with_timeout_opt(100, () => self.output.read_some())
        is Some(Some(_)) {
    ()
  }
}

///|
/// ConPTY renders a screen instead of preserving the original output bytes.
/// Text may be split across reads, so accumulate until the expected text appears.
async fn Ttyd::expect_output_text(self : Ttyd, expected : String) -> Unit {
  let output = @buffer.Buffer()
  while !@utf8.decode_lossy(output.to_bytes()).contains(expected) {
    guard self.output.read_some() is Some(bytes) else {
      fail("terminal closed before displaying \{expected}: \{output}")
    }
    output.write_bytes(bytes)
  }
}

///|
async fn with_ttyd(f : async (Ttyd) -> Unit, exit_with~ : Int32 = 0) -> Unit {
  let ttyd_path = ttyd.wait()
  let harness = pty.wait()
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      let (stdin, input) = @process.write_to_process()
      defer input.close()
      let (output, stdout) = @process.read_from_process()
      defer output.close()
      let (control, stderr) = @process.read_from_process()
      // The owning task group also closes this stream on setup failure.
      group.add_defer(() => control.close())
      let terminal = @process.spawn(
        group,
        harness,
        [ttyd_path, server.addr.port().to_string()],
        stdin~,
        stdout~,
        stderr~,
        cancel_handler=@process.hard_cancel(),
      )
      let (rpc, _) = server.accept()
      {
        defer rpc.close()
        f({ input, output, control, rpc, next_id: 0, })
      }
      input.close()
      let exit_code = terminal.wait()
      guard exit_code == exit_with else {
        fail(
          "terminal harness exited with \{exit_code}, expecting \{exit_with}",
        )
      }
    })
  })
}

///|
async test "tty can be resized" {
  with_ttyd() <| ttyd => {
    assert_eq(ttyd.size(), (24, 80))
    ttyd.resize(25, 81)
    assert_eq(ttyd.size(), (25, 81))
  }
}

///|
async test "resize can interrupt a pending read" {
  with_ttyd() <| ttyd => {
    ttyd.enter_raw_mode()
    @async.with_task_group() <| group => {
      group.spawn_bg() <| () => {
        guard ttyd.read_event() is Some(Resize) else {
          fail("expect exactly one Resize event")
        }
      }
      group.spawn_bg() <| () => {
        @async.sleep(100)
        ttyd.resize(25, 81)
      }
    }
  }
}

///|
async fn expect_read_event_to_timeout(ttyd : Ttyd, timeout~ : Int32) -> Unit {
  try ttyd.read_event(timeout~) catch {
    Timeout => ()
    error => raise error
  } noraise {
    event => fail("expect read_event to timeout, got: \{@debug.Repr(event)}")
  }
}

///|
async test "multiple resize events collapse into one" {
  let sizes = [(25, 81), (26, 82), (27, 83)]
  with_ttyd() <| ttyd => {
    ttyd.enter_raw_mode()
    for (rows, cols) in sizes {
      ttyd.resize(rows, cols)
    }
    guard ttyd.read_event() is Some(Resize) else {
      fail("expect exactly one Resize event, got None or Some(Input)")
    }
    expect_read_event_to_timeout(ttyd, timeout=200)
  }
}

///|
async test "cooked mode respects line discipline" {
  with_ttyd() <| ttyd => {
    @async.with_task_group(group => {
      ttyd.send_input(b"hello")
      let reading = group.spawn(() => ttyd.read_event())
      @async.sleep(200)
      assert_true(reading.try_wait() is None)
      let (enter, line) = if @async.platform is Windows {
        (b", world!\r", b"hello, world!\r\n")
      } else {
        (b", world!\n", b"hello, world!\n")
      }
      ttyd.send_input(enter)
      assert_eq(reading.wait(), Some(Input(line)))
    })
  }
}

///|
async test "raw mode delivers input without line buffering" {
  with_ttyd() <| ttyd => {
    ttyd.enter_raw_mode()
    let text = b"\x1b[A"
    ttyd.send_input(text)
    assert_eq(ttyd.read_exactly(text.length()), text)
  }
}

///|
async test "raw mode entering is idempotent" {
  with_ttyd() <| ttyd => {
    ttyd.enter_raw_mode()
    assert_false(ttyd.is_canonical())
    ttyd.enter_raw_mode()
    assert_false(ttyd.is_canonical())
    // a single leave restores the terminal
    ttyd.leave_raw_mode()
    assert_true(ttyd.is_canonical())
    ttyd.leave_raw_mode()
    assert_true(ttyd.is_canonical())
  }
}

///|
async test "@io.Reader should not consume resize event" {
  with_ttyd() <| ttyd => {
    ttyd.enter_raw_mode()
    @async.with_task_group() <| group => {
      group.spawn_bg() <| () => {
        guard ttyd.read_exactly(6) is b"hello\n" else {
          fail("expect read_exactly to return the input")
        }
        guard ttyd.read_event() is Some(Resize) else {
          fail("expect the resize to be left to read_event")
        }
        expect_read_event_to_timeout(ttyd, timeout=200)
      }
      group.spawn_bg() <| () => {
        @async.sleep(100)
        ttyd.resize(25, 81)
        ttyd.send_input(b"hello\n")
      }
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "cooked mode handles EOF" {
  with_ttyd() <| ttyd => {
    ttyd.send_input(b"\x04")
    guard ttyd.read_event() is None else {
      fail("expect read_event to return None for \\x04 in cooked mode")
    }
  }
}

///|
async test "^C interrupt cooked mode program" {
  let sigint = match @async.platform {
    Windows => -1073741510 // STATUS_CONTROL_C_EXIT (0xC000013A)
    _ => 130
  }
  with_ttyd(exit_with=sigint) <| ttyd => {
    ttyd.send_input(b"\x03")
    // Wait for `ttyd` to die. Returning right away would close the
    // connection, and `ttyd` could exit normally before `^C` reaches it.
    guard ttyd.rpc.read_some() is None else {
      fail("expect ttyd to be killed by Ctrl-C")
    }
  }
}

///|
async test "^C does not interrupt raw mode program" {
  with_ttyd() <| ttyd => {
    ttyd.enter_raw_mode()
    ttyd.send_input(b"\x03")
    guard ttyd.read_exactly(1) is b"\x03" else {
      fail("expected to read ^C as \\x03")
    }
  }
}

///|
async test "cooked mode echoes back" {
  with_ttyd() <| ttyd => {
    if @async.platform is Windows {
      ttyd.drain_output()
      @async.with_task_group(group => {
        let reading = group.spawn(() => ttyd.read_exactly(15))
        ttyd.send_input(b"hello, world!\r")
        ttyd.expect_output_text("hello, world!")
        assert_eq(reading.wait(), b"hello, world!\r\n")
      })
    } else {
      ttyd.send_input(b"hello, world!\n")
      assert_eq(ttyd.output.read_exactly(15), b"hello, world!\r\n")
    }
  }
}

///|
async test "raw mode does not echo back" {
  with_ttyd() <| ttyd => {
    ttyd.enter_raw_mode()
    if @async.platform is Windows {
      ttyd.drain_output()
    }
    let text = b"hello, world!\n"
    ttyd.send_input(text)
    assert_eq(ttyd.read_exactly(text.length()), text)
    let output = @async.with_timeout_opt(200, () => ttyd.output.read_some())
    if output is Some(output) {
      fail("raw mode echos back something: \{@debug.Repr(output)}")
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "@io.Writer writes bytes as is under raw mode" {
  with_ttyd() <| ttyd => {
    ttyd.enter_raw_mode()
    let text = b"hello,\nworld!"
    ttyd.write(text)
    guard ttyd.output.read_exactly(text.length()) == text else {
      fail("@io.Writer fails to write text as is under raw mode")
    }
  }
}

///|
async test "raw mode delivers UTF-8 input" {
  with_ttyd() <| ttyd => {
    ttyd.enter_raw_mode()
    let text = b"\xc3\xa9\xe4\xb8\xad\xf0\x9f\x98\x80"
    ttyd.send_input(text)
    assert_eq(ttyd.read_exactly(text.length()), text)
  }
}

///|
async test "cancelling a parked read keeps the terminal usable" {
  with_ttyd() <| ttyd => {
    ttyd.enter_raw_mode()
    expect_read_event_to_timeout(ttyd, timeout=100)
    ttyd.send_input(b"z")
    assert_eq(ttyd.read_event(), Some(Input(b"z")))
  }
}

///|
async test "a cooked read can be cancelled" {
  with_ttyd() <| ttyd => {
    ttyd.send_input(b"partial")
    expect_read_event_to_timeout(ttyd, timeout=100)
  }
}

///|
#cfg(platform="windows")
async test "writer displays UTF-8 text through ConPTY" {
  with_ttyd() <| ttyd => {
    ttyd.enter_raw_mode()
    ttyd.drain_output()
    ttyd.write(@utf8.encode("héllo 😀"))
    ttyd.expect_output_text("héllo 😀")
  }
}

///|
#cfg(platform="windows")
async test "cooked console preserves Ctrl-Z as input" {
  with_ttyd() <| ttyd => {
    // ReadConsoleW does not apply the CRT's Ctrl-Z-to-EOF translation.
    ttyd.send_input(b"\x1a\r")
    assert_eq(ttyd.read_event(), Some(Input(b"\x1a\r\n")))
  }
}
