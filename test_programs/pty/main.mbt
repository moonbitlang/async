///|
/// Run a command on an isolated PTY (ConPTY on Windows). Arguments are passed
/// directly to the child. See stub.c for the stdin control protocol.
#borrow(args)
extern "C" fn run(args : FixedArray[Bytes]) -> Int32 = "moonbit_async_test_programs_pty_run"

///|
extern "C" fn exit(code : Int32) = "exit"

///|
fn main raise {
  let args = @argparse.Command("pty", positionals=[
    @argparse.PositionArg(
      "command",
      num_args=@argparse.ValueRange(lower=1),
      allow_hyphen_values=true,
    ),
  ]).parse()
  guard args.values.get("command") is Some(command) else {
    fail("expected a command")
  }
  let encoded = FixedArray::make(command.length(), b"")
  for i, arg in command {
    encoded[i] = @utf8.encode(arg)
  }
  exit(run(encoded))
}
