# Terminal (`@moonbitlang/async/tty`)

Minimal, cross-platform access to the controlling terminal: open it, enter and
leave raw mode, query its size, wait for input or resize, write bytes.

Input is delivered as the raw VT byte stream the terminal sends. The package
does no key decoding, no escape-sequence parsing and no screen management;
those belong to libraries built on top of it.

```moonbit nocheck
///|
async fn run() -> Unit {
  let tty = @tty.open()
  tty.enter_raw_mode()
  defer tty.leave_raw_mode()
  let (rows, cols) = tty.size()
  tty.write("\{rows}x\{cols}\r\n")
  while tty.read_event() is Some(event) {
    match event {
      Input(b"q") => break
      Input(bytes) => tty.write("got \{bytes.length()} bytes\r\n")
      Resize => {
        let (rows, cols) = tty.size()
        tty.write("resized to \{rows}x\{cols}\r\n")
      }
    }
  }
}
```

Notes:

- `open()` opens the terminal once and returns the same handle afterwards.
  There is no `close`; the terminal is given back with `leave_raw_mode`, which
  also runs automatically when the event loop exits.
- In raw mode Ctrl-C no longer interrupts the program. It arrives as `Input(b"\x03")`.
- `Resize` carries no size, call `size()`. Several resizes in a row may be
  reported as one event.
- `Tty` implements `@io.Reader` and `@io.Writer`. Only one read, through
  `read_event` or the reader methods, may be in progress at a time;
  starting another one aborts the program, as with any other reader.
- Native only. On Windows `open()` opens the console (`CONIN$`/`CONOUT$`).
  Console input is converted to the same VT byte stream as on Unix, and
  `Resize` is only reported in raw mode.
