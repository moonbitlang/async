# internal/c_buffer

Internal wrapper for C-allocated byte buffers.

## Overview

`@internal/c_buffer` exposes an opaque `Buffer` type and a small set of
FFI-backed helpers used throughout the async runtime. These APIs are unsafe:
they operate on raw pointers and assume correct size, lifetime, and
null-termination guarantees from native code.

This package is **native-only**. The JavaScript backend is not supported.

## API Summary

- `Buffer`: opaque C pointer
- `blit_from_bytes`: copy MoonBit `Bytes` into a C buffer
- `blit_to_bytes`: copy C buffer content into a MoonBit `FixedArray[Byte]`
- `get`: read a single byte by index
- `strlen`: length of a NUL-terminated C string
- `null`, `is_null`, `free`

## Safety and Ownership

- `Buffer` values are raw pointers; no bounds checks are performed.
- `free` must only be called on memory allocated by `malloc` or a compatible
  allocator. Passing `null` is allowed.
- `strlen` requires a valid NUL-terminated sequence.

## Examples

```mbt check
///|
test "null helpers" {
  inspect(Buffer::is_null(null), content="true")
  Buffer::free(null)
}
```
