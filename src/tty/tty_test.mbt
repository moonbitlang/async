///|
fn make_test_prog(name : String) -> @async.Lazy[String] {
  Lazy() <| () => {
    let code = @process.run("moon", [
      "build",
      "test_programs/\{name}",
      "--debug",
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
/// See `test_programs/ttyd`.
priv struct Ttyd {
  input : @process.WriteToProcess
  output : @process.ReadFromProcess
  path : String
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
async fn Ttyd::is_canonical(self : Ttyd) -> Bool {
  let flag = if @async.platform is MacOS { "-f" } else { "-F" }
  let (code, output) = @process.collect_stdout("stty", ["-a", flag, self.path])
  guard code == 0 else { fail("stty failed with \{code}") }
  // `stty -a` lists each flag, prefixed with `-` when it is off.
  let output = output.text()
  if output.contains("-icanon") {
    false
  } else if output.contains("icanon") {
    true
  } else {
    fail("unrecognized `stty -a` output")
  }
}

///|
async fn Ttyd::resize(self : Ttyd, rows : Int32, cols : Int32) -> Unit {
  let code = @process.run("stty") <| [
    if @async.platform is MacOS {
      "-f"
    } else {
      "-F"
    },
    self.path,
    "rows",
    rows.to_string(),
    "cols",
    cols.to_string(),
  ]
  guard code is 0 else { fail("stty failed with \{code}") }
}

///|
async fn with_ttyd(f : async (Ttyd) -> Unit, exit_with~ : Int32 = 0) -> Unit {
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      // We use this two-fold approach so that we don't have to worry about
      // various escaping rules across different shells.
      let setup_script = "stty rows 24 cols 80 && tty && exec '\{ttyd.wait()}' \{server.addr.port()} </dev/null"
      let setup_cmd_arg = "exec sh -c \"$TTYD_SETUP\""
      let args = if @async.platform is MacOS {
        ["-q", "/dev/null", "sh", "-c", setup_cmd_arg]
      } else {
        ["-q", "-e", "-c", setup_cmd_arg, "/dev/null"]
      }
      let (stdin, input) = @process.write_to_process()
      defer input.close()
      let (output, stdout) = @process.read_from_process()
      defer output.close()
      let script = @process.spawn(
        group,
        "script",
        args,
        extra_env={ "TTYD_SETUP": setup_script },
        stdin~,
        stdout~,
      )
      guard output.read_until("\n") is Some(path) else {
        fail("terminal closed before printing its path")
      }
      let (rpc, _) = server.accept()
      {
        defer rpc.close()
        f({ input, output, path: path.trim().to_owned(), rpc, next_id: 0, })
      }
      let exit_code = script.wait()
      guard exit_code == exit_with else {
        fail("script exited with \{exit_code}, expecting \{exit_with}")
      }
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "tty can be resized" {
  with_ttyd() <| ttyd => {
    assert_eq(ttyd.size(), (24, 80))
    ttyd.resize(25, 81)
    assert_eq(ttyd.size(), (25, 81))
  }
}

///|
#cfg(not(platform="windows"))
async test "resize can interrupt a pending read" {
  with_ttyd() <| ttyd => {
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
#cfg(not(platform="windows"))
async test "multiple resize events collapse into one" {
  let sizes = [(25, 81), (26, 82), (27, 83)]
  with_ttyd() <| ttyd => {
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
#cfg(not(platform="windows"))
async test "cooked mode respects line discipline" {
  with_ttyd() <| ttyd => {
    ttyd.input.write("hello")
    expect_read_event_to_timeout(ttyd, timeout=200)
    ttyd.input.write(", world!\n")
    guard ttyd.read_event() is Some(Input(b"hello, world!\n")) else {
      fail("expect line discipline to return one line at once")
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "raw mode delivers input without line buffering" {
  with_ttyd() <| ttyd => {
    ttyd.enter_raw_mode()
    let text = b"\x1b[A"
    ttyd.input.write(text)
    assert_eq(ttyd.read_exactly(text.length()), text)
  }
}

///|
#cfg(not(platform="windows"))
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
#cfg(not(platform="windows"))
async test "@io.Reader should not consume resize event" {
  with_ttyd() <| ttyd => {
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
        ttyd.input.write("hello\n")
      }
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "cooked mode handles EOF" {
  with_ttyd() <| ttyd => {
    ttyd.input.write(b"\x04")
    guard ttyd.read_event() is None else {
      fail("expect read_event to return None for \\x04 in cooked mode")
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "^C interrupt cooked mode program" {
  let sigint = if @async.platform is MacOS { 2 } else { 130 }
  with_ttyd(exit_with=sigint) <| ttyd => {
    ttyd.input.write(b"\x03")
    // Wait for `ttyd` to die. Returning right away would close the
    // connection, and `ttyd` could exit normally before `^C` reaches it.
    guard ttyd.rpc.read_some() is None else {
      fail("expect ttyd to be killed by SIGINT")
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "^C does not interrupt raw mode program" {
  with_ttyd() <| ttyd => {
    ttyd.enter_raw_mode()
    ttyd.input.write(b"\x03")
    guard ttyd.read_exactly(1) is b"\x03" else {
      fail("expected to read ^C as \\x03")
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "cooked mode echoes back" {
  with_ttyd() <| ttyd => {
    let text = "hello, world!\n"
    ttyd.input.write(text)
    guard ttyd.output.read_exactly(text.length() + 1) is b"hello, world!\r\n" else {
      fail("expect cooked mode to echo back text with \\n replaced with \\r\\n")
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "raw mode does not echo back" {
  with_ttyd() <| ttyd => {
    ttyd.enter_raw_mode()
    let text = "hello, world!\n"
    ttyd.input.write(text)
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
