# Terminal Support (`moonbitlang/async/tty`)

## Goal

Add a `tty` package that gives programs one handle on the controlling terminal:
open it, enter and leave raw mode, query its size, wait for input or resize,
write bytes. Every input byte the handle yields is exactly what the terminal
sent, as a VT byte stream on every platform. Windows console input is folded
into that contract by re-encoding `INPUT_RECORD`s into VT sequences below the
FFI line, the way `charmbracelet/ultraviolet` does.

The package is deliberately the bottom layer. It carries no escape-sequence
protocol knowledge upward: no key decoding, no ESC timeouts, no cursor or color
queries, no SGR builders, no command enum. Those belong to downstream libraries
such as `moonbit-community/tty`, which would shrink to sit on top of this
package.

## Public API

```moonbit
// package moonbitlang/async/tty   (native only in v1)

type Tty
pub fn open() -> Tty raise                       // idempotent; /dev/tty | CONIN$ + CONOUT$

pub fn Tty::enter_raw_mode(Self) -> Unit raise   // idempotent
pub fn Tty::leave_raw_mode(Self) -> Unit raise   // idempotent
pub fn Tty::size(Self) -> (Int32, Int32) raise   // rows, cols

pub(all) enum Event {
  Input(Bytes)   // one read's worth of VT bytes, never empty
  Resize         // coalesced; call size() for the new dimensions
}
pub async fn Tty::read_event(Self) -> Event?     // None on EOF
pub suberror ReadInProgress                      // two reads at once

pub impl @io.Reader for Tty                      // same bytes, no resize
pub impl @io.Writer for Tty
```

Design rules behind this shape:

- **One tty per program, opened once.** A process has one controlling
  terminal; two handles on it would split keystrokes and race on raw-mode
  restore. `open()` opens the terminal on the first call and returns the same
  handle on every later call. It raises if there is no controlling terminal.
  This is crossterm's process-global reader with a value to hang methods on.
- **No `close`.** The fd lives as long as the process. Giving the terminal
  back means `leave_raw_mode`; that is what ultraviolet's `console.Close()`
  and bubbletea's shutdown actually do, and neither ever closes the
  `/dev/tty` file they opened. Dropping `close` is also what makes an
  idempotent `open` sound: a shared handle plus `close` is the one
  combination that produces dangling handles.
- `open()` does not inspect stdin or stdout and does not detect `isatty`,
  like ultraviolet's `OpenTTY` and bubbletea. A program that wants to work
  with piped stdio uses `@stdio` directly.
- Raw mode follows crossterm's Unix model on both platforms. The handle keeps a
  snapshot of the original terminal state. `enter_raw_mode` is a no-op when a
  snapshot exists; `leave_raw_mode` restores the snapshot exactly and clears
  it, and is a no-op when there is none. The snapshot is stored only after the
  mode change succeeded, so a failed call leaves the state consistent. No
  `Mode` or `State` value is exposed.
- There is no `with_raw_mode`. The README shows the three-line pattern: enter,
  `defer` leave, run.
- `size` returns rows then columns, matching `struct winsize`.
- `read_event` is the only way to observe resize. It is one job call; the
  job itself waits for input or resize, so callers never build a race and the
  package never does either. Resize is out-of-band: never injected into the
  byte stream, never modelled as an error.
- The `@io.Reader` impl reads through the same job, so a caller using
  `read_until` or `read_exactly` sees the same bytes in the same order. A read
  that is interrupted by a resize returns zero bytes with the flag set; the
  impl loops in that case, so generic readers never see resize.
- `Resize` carries no payload. `size()` is one `ioctl` or
  `GetConsoleScreenBufferInfo`, and a single source of truth avoids a stale
  size when several resizes coalesce. No initial resize is reported; callers
  query `size()` once at startup.

The downstream loop looks like:

```moonbit
let tty = @tty.open()
tty.enter_raw_mode()
defer tty.leave_raw_mode()
while tty.read_event() is Some(event) {
  match event {
    Input(bytes) => decoder.feed(bytes)
    Resize => redraw(tty.size())
  }
}
```

## Non-Goals

- No `isatty`, no stdio-backed constructor, no generic "from reader and writer"
  constructor. Downstream decoders are tested by feeding bytes directly.
- No in-band resize report. Ultraviolet synthesizes `CSI 8 ; h ; w t` on
  Windows; this package does not, so a downstream decoder can never confuse a
  synthesized report with a real XTWINOPS reply to a query it issued itself.
- No resize-as-error. It would fire `errdefer` blocks on every window drag, be
  swallowed by catch-all arms, and cannot be surfaced through the generic
  Reader helpers without losing partial progress.
- No mouse record re-encoding in v1. Modern conhost and Windows Terminal
  translate mouse events into SGR sequences once the application writes
  `CSI ? 1000 h` and friends with VT input enabled, which is the Unix model.
  This must be verified on Windows during implementation; if some conpty
  configuration lacks it, add re-encoding gated on `ENABLE_MOUSE_INPUT`.
- No win32-input-mode (`CSI ... _`) encoding. Raw mode turns on VT input, so
  conhost already delivers special keys as VT characters. If a downstream
  enables `CSI ? 9001 h`, Windows Terminal itself emits `_` sequences as
  characters and they pass through untouched.
- No wasm or JS support in v1. The package starts with
  `supported_targets = "-all+native"` like `raw_fd`. The job shape matches the
  existing wasm host-import seam, so nothing forecloses it.

## Architecture

### Where the code lives

The runtime convention is that every thread-pool job is defined inside
`src/internal/event_loop`, which exports one function per operation, and
that user-facing packages such as `@fs`, `@process` and `@stdio` are thin
wrappers over those exports. The tty follows the same split:

- `src/internal/event_loop/tty.c` and `tty.mbt`: the handle, raw mode, size,
  resize notification and the `tty_read` job. The MoonBit side exports an
  `#external` type `Tty` (C-managed, allocated once, never freed) with the
  methods `open`, `enter_raw`, `leave_raw`, `size`, `take_resize_event` and
  `read`.
- `src/tty`: the public `Tty` struct, which holds the `@event_loop.Tty`, the
  output descriptor and its per-loop `IoHandle`, a `ReaderBuffer`, the
  `read_event` buffer and the "read in progress" flag. No `#cfg` branches.

The only change outside these files is a mask correction in `signal.c`
described under "Resize notification".

```c
// returns NULL with errno set on failure; out_fd receives the output fd
tty_t  *moonbitlang_async_tty_open(moonbit_bytes_t path, int32_t *out_fd);
int32_t moonbitlang_async_tty_enter_raw(tty_t *);
int32_t moonbitlang_async_tty_leave_raw(tty_t *);
int64_t moonbitlang_async_tty_size(tty_t *);          // rows << 32 | cols, -1 on error
int32_t moonbitlang_async_tty_take_resize_event(tty_t *);

// blocks until input or resize, fills buf with VT bytes
struct tty_read_job *moonbitlang_async_make_tty_read_job(
  tty_t *tty, char *buf, int32_t offset, int32_t len);
```

`struct tty` on Unix:

```c
struct tty {
  int32_t        in_fd;      // open("/dev/tty", O_RDWR | O_NOCTTY | O_CLOEXEC), blocking
  int32_t        sig_fd;     // signalfd (Linux) / kqueue EVFILT_SIGNAL (macOS) for SIGWINCH
  struct termios state;      // valid iff is_in_raw
  int32_t        is_in_raw;
  int32_t        resized;    // set by the job, taken by read_event
};
```

`struct tty` on Windows (not implemented yet, every entry point fails with
`ERROR_CALL_NOT_IMPLEMENTED`):

```c
struct tty {
  HANDLE  in;              // CreateFileW("CONIN$"),  non-overlapped
  HANDLE  out;             // CreateFileW("CONOUT$"), for size and output mode only
  HANDLE  cancel_event;    // auto-reset; the job's cancel_handler does SetEvent
  DWORD   in_state, out_state;
  int32_t is_in_raw;
  int32_t resized;
  WCHAR   pending_high;    // unpaired high surrogate from the last key-down record
  SHORT   last_rows, last_cols;
  char    pending[4];      // UTF-8 bytes produced but not yet delivered
  int32_t pending_len;
};
```

The `out_fd` written by `open` is `fcntl(in_fd, F_DUPFD_CLOEXEC)` on Unix and
a second `CreateFileW("CONOUT$")` on Windows. It is owned by the MoonBit
output `IoHandle`, so the C struct never shares an fd with it. On Windows the
struct keeps its own `out` because `GetConsoleScreenBufferInfo` and the
output half of `SetConsoleMode` need an output handle.

The handle is a plain `malloc` like every other C object the runtime hands to
MoonBit (`Job`, `AddrInfo`, `@c_buffer.Buffer`); there is no finalizer. A
program has one terminal and never closes it, and the terminal is restored by
the event-loop exit hook, not by garbage collection.

### The MoonBit side

```moonbit
pub async fn Tty::read_event(self : Self) -> Event? {
  if self.resize_pending || self.handle.take_resize_event() {   // left by a previous read
    self.resize_pending = false
    return Some(Resize)
  }
  let n = self.read_once(...)                                  // one tty_read job, cancellable
  if n > 0 { return Some(Input(...)) }                          // bytes first; a flag set
                                                                // alongside waits for the next call
  if self.handle.take_resize_event() { return Some(Resize) }   // wait ended by a resize
  None                                                          // EOF
}
```

`take_resize_event` reads and clears `resized` through FFI, because the
struct is opaque to MoonBit. It is called only after the job has completed,
when the worker no longer touches the struct, so it needs no atomics.

- `read_once` guards the "read in progress" flag and raises `ReadInProgress`
  if a read is already parked. It then calls `@event_loop.Tty::read`, which
  builds one `tty_read` job on the `FixedArray[Byte]` with `#owned(buf)` and
  runs it with `perform_job_in_worker(cancellable=true)`.
- The `@io.Reader` impl reads through the same job. When the job returns zero
  bytes with the resize flag set, the impl records `resize_pending` and reads
  again, so generic readers never see a resize and the next `read_event`
  still reports it.
- `write_once` delegates to the output `IoHandle`, created lazily with
  `IoHandle::from_fd(out_fd, kind=CharDevice, is_async=false)` for the event
  loop that is running, and detached by the exit hook. On Windows that handle
  will be a console handle, so the existing `WriteConsoleW` path with UTF-8
  to UTF-16 conversion is reused unchanged.

### Why a thread-pool job and not the event bus

- Windows console input handles cannot be associated with an IOCP. `ReadFile`
  ignores `OVERLAPPED` on `CONIN$` and `ReadConsoleInputW` is synchronous. The
  runtime already reads console stdin through a worker for this reason.
- macOS `kqueue` does not support `/dev/tty`, which is why libuv keeps a
  `select` fallback and why the current community package avoids registering
  it. `poll` does not work on it either (`poll(2)` BUGS: "The poll() system
  call currently does not support devices"; see
  `tty-probes/dev_tty_pollable.c`). A macOS read ends in a worker and a
  `select` either way.
- Linux could use `epoll`, but doing so would require a second, `#cfg`-gated
  read path. One path is easier to keep correct than two.

The cost is one parked worker per outstanding read and a wake-up hop from the
worker to the loop. Other IO is unaffected; latency is invisible at keyboard
rates.

### The read job

Unix:

```c
ready = poll({in_fd, sig_fd})            // Linux; select() on macOS; cancellable region
if (!(ready & INPUT)) {                  // only the resize fd fired
  if (drain(sig_fd)) tty->resized = 1;   // read the signalfd / kevent until empty
  return 0;
}
return read(in_fd, buf + offset, len);   // cancellable region
```

When both fds are ready the input wins and `sig_fd` stays readable, so the
next call returns the resize without blocking. Zero bytes from `read` is EOF.

Windows:

1. `WaitForMultipleObjects` on `CONIN$` and the cancel event (cancellable
   region).
2. `GetNumberOfConsoleInputEvents`, then one `ReadConsoleInputW` for at most
   `len / 4` records (minimum one), since each record expands to at most four
   bytes. Only a caller buffer smaller than four bytes can overflow, hence the
   4-byte `pending` area.
3. Encode the whole batch into `buf`, setting `resized` if a size record
   changed `srWindow`. If the batch produced no bytes and did not set the
   flag, loop back to step 1; returning zero bytes otherwise means EOF.

Both: the cancellable region wraps only the blocking call. Encoding and
bookkeeping run outside it. Records already consumed by `ReadConsoleInputW`
are gone from the console and must be delivered even if cancellation arrived
meanwhile. The existing "signal after syscall" retry logic in
`cancellation_signal_handler` plus the cancellation swallow in `wait_for_job`
make a completed read lossless. The job never touches `is_in_raw` or the
states; the main thread never touches the encoder fields. That is the whole
thread-safety story.

### Record encoding on Windows

| Record | Effect |
|---|---|
| `KEY_EVENT`, key down | UTF-8 of `UnicodeChar`; surrogate pairs joined across records |
| `KEY_EVENT`, key up, or `UnicodeChar == 0` | dropped (conhost already produced VT for special keys) |
| `WINDOW_BUFFER_SIZE_EVENT` | dropped from the stream; sets `resized` if `srWindow` differs from the last report |
| `FOCUS_EVENT` | `CSI I` / `CSI O` |
| `MOUSE_EVENT`, `MENU_EVENT` | dropped in v1 |

The record's own `dwSize` is the screen buffer size, which on legacy conhost
includes scrollback height, so the window rectangle from
`GetConsoleScreenBufferInfo` is used instead. Legacy conhost only fires the
record when the buffer size changes; a height-only window resize can go
unreported. Mitigation: compare `srWindow` against the last report on every
batch, so a missed resize is reported with the next input. Windows Terminal
and ConPTY resize the buffer with the viewport, so every resize fires there.

Only the key-down surrogate half is carried, since key-up characters are
dropped. The encoder takes a portable packed struct with the 20-byte
`INPUT_RECORD` layout rather than the Windows type, and is exported so MoonBit
tests can feed hand-built records on Linux and macOS.

### Resize notification

Resize never touches the event loop. On both platforms it is observed by the
read job and reported through the handle's `resized` field.

**Unix: a descriptor that reflects the pending signal.** `tty_open` blocks
`SIGWINCH` in the calling thread; worker threads and the `sigwait` thread
already block every signal. Nothing ever handles the signal, so it stays
pending for the process. `tty_open` also creates `sig_fd`, a `signalfd` for
`SIGWINCH` on Linux and a `kqueue` with an `EVFILT_SIGNAL` entry on macOS,
which becomes readable while the signal is pending. The read job waits on
`in_fd` and `sig_fd` together and drains `sig_fd` when it fires. This is
level-triggered, so a resize that happens while no read is parked is reported
by the next read without blocking, and a burst collapses into one event
(`kevent` even counts them in `data`).

A plain signal handler cannot do this job. The first implementation
installed a `SIGWINCH` handler setting a flag and let the worker unblock the
signal only inside `pselect`, relying on the pending signal being delivered
when the mask opens. That holds on Linux, but on macOS a signal generated
while every thread blocks it is parked on one particular thread (the first
one) and is never handed to another thread that unblocks it later. A resize
arriving between two reads was lost, and a resize during a read could end up
on the main thread and leave the worker parked forever. Both cases were
reproduced with a standalone C program before switching; the programs behind
this and the `kqueue` claims below are in `tty-probes/`.

The `signal.c` correction is still required, for Linux: `sigwait_thread_worker`
used to set its mask to its wait set with `SIG_SETMASK`, leaving every other
signal unblocked there. The kernel would then deliver `SIGWINCH` to that
thread, where the default action (ignore) consumes it and the `signalfd`
never sees it. The thread now blocks every signal and `sigwait`s on its set,
which is the correct form regardless. `kqueue` records the signal at
generation time, so macOS does not depend on this, but the mask fix is what
makes Linux work.

**Windows: the record carries it.** `WINDOW_BUFFER_SIZE_EVENT` is seen by the
job while draining `ReadConsoleInputW`, sets `resized`, and is dropped
from the byte stream. The console control handler and the notify channel are
not involved. A resize is therefore only observed while a read is parked, and
`read_event` always has one parked; a program that stops reading stops
noticing resizes, which is the same on both platforms in practice.

Alternatives considered and rejected, in case the question returns:

- In-band `CSI 8 ; rows ; cols t`: see Non-Goals.
- `SIGWINCH` handler plus `pselect`: lossy on macOS, see above.
- A per-handle wake pipe written by the event loop's signal demultiplexer, or
  by a C-side fd registry in the `sigwait` thread: works, but adds two fds,
  a two-fd `poll`, and either a loop-side slot or C-side policy.
- A self-pipe written by a `SIGWINCH` handler, as crossterm does through
  `signal_hook`: works, but requires the signal to be unblocked somewhere and
  a handler installed, and `signalfd`/`kqueue` give the same fd without
  either.
- An `IoHandle::interrupt_read` primitive that wakes a parked coroutine or
  `SIGUSR2`s a worker: no fd, but it touches the core read path and reuses
  the cancellation signal for a non-cancellation purpose.
- A MoonBit-side race in `read_event` with a single-slot waiter: lossless
  but the most code of all.

### Raw mode

Unix: `cfmakeraw` with `VMIN=1`, `VTIME=0`, applied with
`tcsetattr(TCSANOW)` to the input fd. The snapshot is stored only after
`tcsetattr` succeeded.

Windows input: clear `ENABLE_ECHO_INPUT`, `ENABLE_LINE_INPUT`,
`ENABLE_PROCESSED_INPUT`, `ENABLE_QUICK_EDIT_MODE`; set
`ENABLE_VIRTUAL_TERMINAL_INPUT`, `ENABLE_WINDOW_INPUT`,
`ENABLE_EXTENDED_FLAGS`. Without VT input special keys never become VT bytes;
without window input there are no resize records; with quick-edit on, a mouse
click freezes output. If `SetConsoleMode` rejects the VT flag the console
predates VT support and `enter_raw_mode` raises rather than half-applying.

Windows output: set `ENABLE_VIRTUAL_TERMINAL_PROCESSING` and
`DISABLE_NEWLINE_AUTO_RETURN` on `CONOUT$`.

Consequences to document:

- Ctrl-C stops being a cancellation signal in raw mode on both platforms
  (`ISIG` cleared on Unix, `ENABLE_PROCESSED_INPUT` cleared on Windows). It
  arrives as byte `0x03`.
- Outside raw mode on Windows, reads go through the existing cooked
  `ReadConsoleW` path, so line-oriented reading keeps working. The record
  path is used only while raw, which also means `Resize` is only delivered
  while raw on Windows.
- To run a child process in the foreground or suspend, call `leave_raw_mode`
  before and `enter_raw_mode` after. The child opens its own `/dev/tty`; the
  parent keeping its fd open does not interfere.

### Lifetime

The handle follows the `stdio.mbt` pattern: a process-lifetime object attached
to whichever event loop is running.

- `open()` is synchronous: opening `/dev/tty` does not block, and nothing in
  it needs the event loop. On first use it creates the C handle, stores the
  `Tty` in the package-level `Ref`, and registers one
  `@event_loop.register_hook(exit=...)`. Later calls return the stored value.
- The output `IoHandle` is created lazily by the first write on each event
  loop, because `IoHandle::from_fd` needs a running loop and a handle cannot
  be re-attached to a later loop from outside `event_loop`. The exit hook
  calls `leave_raw_mode` (errors swallowed) and detaches the handle, which is
  what keeps `check_fd_leak` quiet and makes a program that enters
  `with_event_loop` several times, as tests do, keep working across loops.
  The hook mechanism is process-lifetime and has no unregister, which is
  exactly the shape a singleton wants.
- `KilledBySignal` propagates through `defer`, so a Ctrl-C outside raw mode
  still runs the exit hook, and the terminal is restored before
  `terminate_process_by_signal`. An uncaught error reaches the hook the same
  way.
- The loop never exits with a parked job: every read is owned by a task, and
  structured concurrency cancels the task, hence the job, before `main`
  completes.

## Target Files And Surfaces

- `src/internal/event_loop/tty.c`: handle struct, open, raw mode, size,
  `sig_fd` creation and draining, `tty_read` job.
- `src/internal/event_loop/tty.mbt`: `#external pub type Tty` and its
  methods, `Job::tty_read`. Native only.
- `src/internal/event_loop/signal.c`: `sigfillset` mask in
  `sigwait_thread_worker`.
- `src/tty/moon.pkg`: `supported_targets = "-all+native"`,
  `max_concurrent_tests = 1`, native stub `test_stub.c`.
- `src/tty/tty.mbt`: `Tty`, `Event`, `ReadInProgress`, `open`, `read_event`,
  Reader and Writer impls, singleton `Ref`, exit hook.
- `src/tty/test_stub.c`: pseudo-terminal helpers for tests only.
- `src/tty/tty_wbtest.mbt`, `src/tty/README.mbt.md`.

## API And Interface Diff

- New package `moonbitlang/async/tty` with the surface listed above.
- `src/internal/event_loop/pkg.generated.mbti` gains the `Tty` type and its
  six methods. It is an internal package.
- `src/signal/pkg.generated.mbti` unchanged. No other public package changes.

## Validation

Done for Unix (`moon test src/tty --target native`, 8 tests on macOS):

- White-box tests create a pty pair with `posix_openpt`, open the slave
  through the internal `Tty::open_path`, and drive the master through
  `@raw_fd.RawFd`: cooked mode holds back a partial line, raw mode is
  idempotent and restores exactly, `size` follows `TIOCSWINSZ`, a
  `kill(getpid(), SIGWINCH)` during a parked read and while idle is reported
  once, a burst of three is coalesced, `with_timeout` cancels a parked read
  and the terminal stays usable, a second concurrent read raises
  `ReadInProgress`, and the Reader and Writer impls round-trip bytes with a
  resize seen by a plain read surfacing at the next `read_event`.
- `SIGWINCH` is process-wide, so the package runs its tests one at a time
  (`max_concurrent_tests = 1`); concurrent tests made the resize tests wake
  the parked reads of the others.
- `moon test src/signal src/stdio src/process --target native` passes with
  the `signal.c` change.
- `moon fmt`, `moon check --target native`, `moon info`, `git diff --check`.

Still to do:

- Record encoder: black-box tests on every OS through the portable-struct
  export, covering ASCII, BMP, surrogate pairs split across batches, key-up
  drops, focus, resize dedupe and the empty-batch loop.
- Linux run of the pty tests (the `signalfd` path).
- Windows console behaviour: manual, CI runners have no console.

## Known Limitations

- `Tty` and `@stdio.stdin` both consume the single console input buffer on
  Windows; records taken by one are invisible to the other. Do not read the
  same console through both.
- `SIGWINCH` is blocked in the main thread once `open()` has been called.
  `@process` restores the mask the runtime started with for its children, but
  a child created by foreign code through plain `fork`/`exec` inherits the
  blocked signal and will not see resizes.
- On macOS the wait uses `select`, so the terminal and `sig_fd` descriptors
  must be below `FD_SETSIZE` (1024). They are opened early in practice.
- Resize is not ordered with respect to nearby keystrokes.
- A resize is only observed by a read. `read_event` always has one parked,
  so this only matters for programs that stop reading; with the
  level-triggered `sig_fd` the resize is still reported by the next read.
- The terminal fd stays open for the life of the process once `open()` has
  been called. This matches crossterm, ultraviolet and bubbletea.

## Open Questions

- Whether conhost's native VT mouse translation covers every ConPTY setup.
  Decides whether mouse re-encoding is needed after v1.
- Whether `Resize` should carry `(rows, cols)` queried at delivery time.
  Current decision: no payload, callers use `size()`.
