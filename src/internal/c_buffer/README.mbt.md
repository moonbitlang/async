# C Buffer API (`@moonbitlang/async/internal/c_buffer`)

A low-level C buffer interface for MoonBit async operations. This package provides efficient interoperation with C memory buffers, enabling zero-copy data transfer between MoonBit and C code.

## Table of Contents

- [Overview](#overview)
- [Buffer Type](#buffer-type)
- [Memory Operations](#memory-operations)
  - [Copying from MoonBit to C](#copying-from-moonbit-to-c)
  - [Copying from C to MoonBit](#copying-from-c-to-moonbit)
- [String Operations](#string-operations)
- [Memory Management](#memory-management)
- [Safety Considerations](#safety-considerations)
- [Types Reference](#types-reference)

## Overview

The C buffer package provides a direct interface to C memory regions, allowing efficient data exchange between MoonBit async operations and C code. This is particularly useful for interfacing with system libraries, network operations, or other low-level operations that require direct memory access.

## Buffer Type

The core type is `Buffer`, which represents a raw C pointer:

```moonbit test
// A Buffer represents a C memory pointer
fn init {
  let buffer : Buffer = null // Initialize with null
}
```

The `null` constant provides a safe default value representing a null pointer.

## Memory Operations

### Copying from MoonBit to C

To copy data from MoonBit `Bytes` to a C buffer:

```moonbit test
fn init {
  let data = b"Hello, World!"
  let buffer = null // In practice, allocate via C FFI
  
  // Copy 13 bytes starting from offset 0
  // buffer.blit_from_bytes(data, offset=0, len=13)
}
```

This operation uses the `blit_from_bytes` method which efficiently copies memory from a MoonBit-managed `Bytes` object to the C buffer.

### Copying from C to MoonBit

To copy data from a C buffer to MoonBit:

```moonbit test
fn init {
  let buffer = null // In practice, C buffer with data
  let array : FixedArray[Byte] = FixedArray::make(100, b'0')
  
  // Copy 50 bytes to array starting at offset 0
  // buffer.blit_to_bytes(array, offset=0, len=50)
}
```

The `blit_to_bytes` method copies data from the C buffer into a MoonBit `FixedArray[Byte]`.

## String Operations

For null-terminated C strings, you can get the length using:

```moonbit test
fn init {
  let buffer = null // In practice, C buffer containing "Hello\0"
  // let length = buffer.strlen() // Returns 5
}
```

This is equivalent to the C `strlen` function and calculates the number of characters before the first null terminator.

## Memory Management

C buffers must be explicitly freed to prevent memory leaks:

```moonbit test
fn init {
  let buffer = null // In practice, allocated buffer
  // ... use buffer for operations
  // buffer.free() // Release memory
}
```

**Important**: After calling `free()`, the buffer must not be used again.

## Safety Considerations

The C buffer API requires careful memory management:

- **Allocation**: Buffers must be properly allocated before use
- **Bounds**: Never access beyond the allocated buffer size
- **Lifetime**: Manually manage buffer lifetime with `free()`
- **Null Safety**: Use the `null` constant for safe initialization
- **Double-free**: Avoid freeing the same buffer twice

### Safe Usage Pattern

```moonbit test
fn init {
  // Initialize with null
  let mut buffer = null
  
  // ... allocate buffer (via C FFI)
  // Use buffer for operations
  let data = b"example"
  // buffer.blit_from_bytes(data, offset=0, len=7)
  
  // Always free when done
  // buffer.free()
  buffer = null // Reset to null for safety
}
```

## Types Reference

### Buffer

An external type representing a C memory pointer.

### Methods

#### blit_from_bytes

Copies data from MoonBit `Bytes` to C buffer.

#### blit_to_bytes

Copies data from C buffer to MoonBit `FixedArray[Byte]`.

#### strlen

Returns the length of a null-terminated C string.

#### free

Frees the C buffer memory.

### Constants

#### null

A null buffer constant for safe initialization.
