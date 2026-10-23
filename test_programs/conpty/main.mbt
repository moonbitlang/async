///|
/// Windows counterpart of `script` for the TTY tests. The argument is a Windows
/// command line, not a shell command. See stub.c for the stdin control protocol.
#cfg(platform="windows")
#borrow(command)
extern "C" fn run(command : String) -> Int32 = "moonbitlang_test_conpty_run"

///|
extern "C" fn exit(code : Int32) = "exit"

///|
fn main raise {
  let args = @argparse.Command("conpty", positionals=[
    @argparse.PositionArg("command", num_args=@argparse.ValueRange::single()),
  ]).parse()
  guard args.values.get("command") is Some([command]) else {
    fail("expected a command line")
  }
  exit(run(command))
}

///|
#cfg(not(platform="windows"))
fn run(command : String) -> Int32 raise {
  fail("cannot run \{command}: conpty is only available on Windows")
}
