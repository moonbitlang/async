# File Descriptor Utilities

This package provides low-level utilities for managing file descriptors in MoonBit's async runtime.
It offers functions to control file descriptor behavior such as blocking/non-blocking modes, 
close-on-exec flags, and pipe creation.

## Overview

The `fd_util` package contains essential file descriptor manipulation functions that are used
internally by the async runtime. These functions provide a safe wrapper around system calls
for file descriptor operations.

## Functions

### File Descriptor Mode Control

- **`set_blocking(fd, context~)`** - Configure a file descriptor for blocking I/O
- **`set_nonblocking(fd, context~)`** - Configure a file descriptor for non-blocking I/O
- **`set_cloexec(fd, context~)`** - Set the close-on-exec flag

### Pipe Operations

- **`pipe(context)`** - Create a unidirectional pipe for inter-process communication

### Resource Management

- **`close(fd, context~)`** - Close a file descriptor and release associated resources

## Usage Examples

### Creating and Configuring a Pipe

```moonbit
test "pipe example" {
  // Create a pipe for communication
  let result = @fd_util.pipe("creating IPC pipe")
  let read_fd = result.0
  let write_fd = result.1
  
  // Configure the read end as non-blocking
  @fd_util.set_nonblocking(read_fd, context="configuring read end")
  
  // When done, close both ends
  @fd_util.close(read_fd, context="closing read end")
  @fd_util.close(write_fd, context="closing write end")
}
```

### Configuring File Descriptors

```moonbit
test "fd config" {
  // Create a pipe first to get valid file descriptors
  let result = @fd_util.pipe("creating test pipe")
  let fd = result.0
  
  // Set the file descriptor to blocking mode
  @fd_util.set_blocking(fd, context="configuring fd for blocking IO")
  
  // Clean up
  @fd_util.close(fd, context="cleanup")
  @fd_util.close(result.1, context="cleanup")
}
```

### Setting Close-on-Exec Flag

```moonbit  
test "cloexec" {
  // Create a pipe to get a valid file descriptor
  let result = @fd_util.pipe("creating test pipe")
  let fd = result.0
  
  // Set close-on-exec flag (note: pipe() already sets this automatically)
  @fd_util.set_cloexec(fd, context="setting close-on-exec")
  
  // Clean up
  @fd_util.close(fd, context="cleanup")
  @fd_util.close(result.1, context="cleanup")
}
```

## Error Handling

All functions in this package can raise errors when the underlying system calls fail.
The functions use the `@os_error.check_errno` function to provide meaningful error
information based on the system's errno value.

```moonbit
test "error handling" {
  try {
    let result = @fd_util.pipe("creating pipe")
    let r = result.0
    let w = result.1
    // Use the pipe...
    @fd_util.close(r, context="cleanup")
    @fd_util.close(w, context="cleanup")
  } catch {
    _ => println("Failed to create pipe")
  }
}
```

## Implementation Notes

- All functions that create file descriptors automatically set the close-on-exec flag
- The package uses FFI to call native system functions
- Error contexts are provided for better debugging and error reporting
- File descriptors are represented as `Int` values

## Platform Support

This package provides cross-platform file descriptor utilities that work on Unix-like systems
including Linux, macOS, and other POSIX-compliant operating systems.
