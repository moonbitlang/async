# OS Error Handling

This package provides OS-level error handling utilities for MoonBit async operations. It wraps system errno values with contextual information and provides utilities for working with non-blocking I/O errors.

## Overview

The `os_error` package offers:

- **OSError type**: A structured error type that combines errno values with context
- **Error checking utilities**: Functions to check and handle system errors
- **Non-blocking I/O support**: Utilities to detect non-blocking I/O errors

## Usage

### Basic Error Handling

```moonbit
test "check_errno_example" {
  // This would normally be called after a system operation
  // For testing, we assume errno is 0 (no error)
  let current_errno = get_errno()
  if current_errno == 0 {
    // No error case - function would return normally
    inspect(true, content="check_errno works when no error")
  }
}
```

### Working with OSError

```moonbit
test "oserror_example" {
  let error = OSError(2, context="file operation")
  // OSError can be pattern matched
  let OSError(errno, context~) = error
  inspect(errno == 2, content="OSError errno is correct")
  inspect(context == "file operation", content="OSError context is correct")
}
```

### Non-blocking I/O Error Detection

```moonbit
test "nonblocking_io_check" {
  // Check if current errno indicates non-blocking I/O error
  let is_nonblocking = is_nonblocking_io_error()
  inspect(is_nonblocking, content="is_nonblocking_io_error returns bool")
}
```

### Getting Current Errno

```moonbit
test "get_errno_example" {
  let errno : Int = get_errno()
  // errno should be 0 initially in test environment
  inspect(errno, content="get_errno returns Int")
}
```

## API Reference

### Types

#### `OSError`

A structured error type that represents OS-level errors:

```moonbit
pub(all) suberror OSError {
  OSError(Int, context~ : String)
}
```

- **errno**: The system errno value
- **context**: Descriptive context about where the error occurred

### Functions

#### `get_errno() -> Int`

Returns the current errno value from the system.

#### `is_nonblocking_io_error() -> Bool`

Checks if the current errno indicates a non-blocking I/O error.

#### `OSError::is_nonblocking_io_error(err : OSError) -> Bool`

Checks if a specific OSError represents a non-blocking I/O error.

#### `check_errno(context : String) -> Unit raise OSError`

Checks the current errno and raises an OSError if it indicates an error.

## Error Codes

The package works with standard POSIX errno values. Common non-blocking I/O errors include:

- `EAGAIN` (11): Resource temporarily unavailable
- `EWOULDBLOCK`: Operation would block (often same as EAGAIN)

## Platform Support

This package is designed to work with POSIX-compliant systems and provides C FFI bindings for errno handling.
