# Controlling terminal

On native targets, `moonbitlang/async/tty` shares the controlling terminal
with `moonbitlang/core/async/tty`. Calls to `open()` in the same event loop
return the same terminal, including its input buffer and raw-mode state.

```moonbit check
///|
pub async fn echo_input() -> Unit {
  let tty : @tty.Tty = @tty.open()
  tty.enter_raw_mode()
  defer tty.leave_raw_mode()
  for ;; {
    match tty.wait_resize() {
      Resize => continue
      Input =>
        match tty.read() {
          None | Some(b"q") => break
          Some(bytes) => tty.write(bytes)
        }
    }
  }
}
```
