# internal/io_buffer

Sliding-window buffer used by the async I/O stack.

## Overview

`@internal/io_buffer` provides a small, low-level `Buffer` type used by
`@io.ReaderBuffer` and other internal readers. The buffer tracks three pieces of
state:

- `buf`: the underlying `FixedArray[Byte]`
- `start`: offset of the first valid byte
- `len`: number of valid bytes

This package is intentionally minimal and does not enforce invariants beyond
these fields. It is meant for internal use.

## API

- `Buffer::new(size)` creates an empty buffer with the given capacity.
- `Buffer::clear` drops data and releases storage.
- `Buffer::enlarge_to(n)` ensures there is space for `n` bytes starting from
  `start`, compacting or reallocating as needed.
- `Buffer::drop(n)` consumes `n` bytes from the front.

## Examples

```mbt check
///|
test "basic window management" {
  let buf = @io_buffer.Buffer::new(6)
  buf.buf[0] = b'a'
  buf.buf[1] = b'b'
  buf.buf[2] = b'c'
  buf.len = 3

  // Consume two bytes.
  @io_buffer.Buffer::drop(buf, 2)
  inspect(buf.start, content="2")
  inspect(buf.len, content="1")
}
```

```mbt check
///|
test "compaction preserves data" {
  let buf = @io_buffer.Buffer::new(5)
  buf.buf[3] = b'x'
  buf.buf[4] = b'y'
  buf.start = 3
  buf.len = 2
  @io_buffer.Buffer::enlarge_to(buf, 4)
  let view = buf.buf.unsafe_reinterpret_as_bytes()[:buf.len]
  inspect(view, content="b\"xy\"")
}
```

```mbt check
///|
test "resize rounds up to 1024 bytes" {
  let buf = @io_buffer.Buffer::new(4)
  @io_buffer.Buffer::enlarge_to(buf, 7)
  inspect(buf.buf.length(), content="1024")
}
```

## Notes

- The reallocation size is rounded up to 1024-byte segments.
- `clear` releases storage by replacing the internal buffer with an empty array.
