# Event Loop Package (`@moonbitlang/async/internal/event_loop`)

The event loop package provides the core asynchronous I/O infrastructure for MoonBit's async runtime. It manages file descriptor polling, timers, process lifecycle, and worker thread coordination to enable efficient non-blocking operations.

## Table of Contents

- [Overview](#overview)
- [Core Functions](#core-functions)
  - [Event Loop Management](#event-loop-management)
  - [I/O Operations](#io-operations)
  - [Process Management](#process-management)
  - [Timer Operations](#timer-operations)
- [File System Operations](#file-system-operations)
- [Network Operations](#network-operations)
- [Types Reference](#types-reference)
- [Error Handling](#error-handling)
- [Examples](#examples)
- [Best Practices](#best-practices)

## Overview

The event loop is the heart of MoonBit's asynchronous runtime, providing:

- **Non-blocking I/O**: File descriptor polling using platform-specific mechanisms (epoll on Linux, kqueue on macOS)
- **Timer management**: Precise scheduling of delayed operations
- **Process management**: Asynchronous process spawning and waiting
- **Worker thread pool**: Handling blocking operations without stalling the event loop
- **Coroutine integration**: Seamless suspension and resumption of async operations

## Core Functions

### Event Loop Management

The event loop lifecycle is managed through these core functions:

```moonbit
///|
test "basic event loop usage" {
  with_event_loop(async fn() {
    // Your async code here
    sleep(100)  // Non-blocking delay
    println("Event loop is running!")
  })
}
```

```moonbit
///|
test "event loop hooks" {
  register_hook(
    init=fn() { println("Event loop starting") },
    exit=fn() { println("Event loop stopping") }
  )
  
  with_event_loop(async fn() {
    sleep(50)
  })
}
```

### I/O Operations

The event loop provides efficient asynchronous I/O operations:

```moonbit
///|
test "async file I/O" {
  with_event_loop(async fn() {
    // Open a file for writing
    let fd = open("test_file.txt", flags=0o102, mode=0o644, context="test")
    
    // Write data asynchronously
    let data = b"Hello, World!"
    let _ = write(fd, data, offset=0, len=data.length(), can_poll=false, context="test")
    
    // Read data back
    let buffer = FixedArray::make(100, b'\x00')
    let _ = read(fd, buffer, offset=0, len=100, can_poll=false, context="test")
    
    // Close the file descriptor
    close_fd(fd)
    
    // Clean up
    remove("test_file.txt", context="cleanup")
  })
}
```

### Process Management

Asynchronous process operations allow spawning and waiting for child processes:

```moonbit
///|
test "process spawning" {
  with_event_loop(async fn() {
    // Spawn a simple echo command
    let args = FixedArray::from_array([Some(b"echo"), Some(b"Hello from child process!")])
    let pid = spawn(
      b"/bin/echo",
      args,
      env=[],
      stdin=-1,
      stdout=-1,
      stderr=-1,
      cwd=None,
      context="test"
    )
    
    // Wait for the process to complete
    wait_pid(pid)
    println("Process completed")
  })
}
```

### Timer Operations

The event loop provides precise timer functionality:

```moonbit
///|
test "timer operations" {
  with_event_loop(async fn() {
    let start_time = @time.ms_since_epoch()
    
    // Sleep for 100 milliseconds
    sleep(100)
    
    let end_time = @time.ms_since_epoch()
    let elapsed = end_time - start_time
    
    // Should have slept for at least 100ms
    if elapsed >= 100L {
      println("Timer worked correctly")
    }
  })
}
```

## File System Operations

The event loop provides comprehensive file system operations:

```moonbit
///|
test "file system operations" {
  with_event_loop(async fn() {
    let test_dir = "test_directory"
    let test_file = "test_directory/test_file.txt"
    
    // Create directory
    mkdir(test_dir, mode=0o755, context="test")
    
    // Create and write to file
    let fd = open(test_file, flags=0o102, mode=0o644, context="test")
    let _ = write(fd, b"Test content", offset=0, len=12, can_poll=false, context="test")
    
    // Sync file to disk
    fsync(fd, only_data=false, context="test")
    close_fd(fd)
    
    // Get file status
    let _ = stat(test_file, follow_symlink=true, context="test")
    
    // Test file accessibility
    let accessible = access(test_file, amode=0, context="test")
    if accessible == 0 {
      println("File is accessible")
    }
    
    // Clean up
    remove(test_file, context="cleanup")
    rmdir(test_dir, context="cleanup")
  })
}
```

## Network Operations

Asynchronous network operations for socket programming:

```moonbit
///|
test "network address resolution" {
  with_event_loop(async fn() {
    match getaddrinfo("localhost", context="test") {
      Ok(_) => println("Successfully resolved localhost")
      Err(error) => println("Resolution failed: " + error)
    }
  })
}
```

## Types Reference

### Core Types

- **`Directory`**: Handle for reading directory contents
- **`DirectoryEntry`**: Single entry in a directory listing
- **`Stat`**: File status information structure
- **`AddrInfo`**: Network address information for socket operations

### Function Categories

**Event Loop Management:**
- `with_event_loop`: Main entry point for running async code
- `register_hook`: Register initialization/cleanup callbacks

**I/O Operations:**
- `read`: Asynchronous file/socket reading
- `write`: Asynchronous file/socket writing
- `close_fd`: Close file descriptor and remove from polling

**File System:**
- `open`: Open files with specified flags and permissions
- `stat`: Get file metadata and status information
- `mkdir/rmdir`: Directory creation and removal
- `remove`: File deletion
- `fsync`: Synchronize file data to storage
- `access`: Test file accessibility
- `readdir`: Read directory entries
- `realpath`: Resolve symbolic links to canonical paths

**Network:**
- `recvfrom/sendto`: Socket data transfer with address information
- `connect`: Establish socket connections
- `accept`: Accept incoming connections
- `getaddrinfo`: Resolve hostnames to network addresses

**Process:**
- `spawn`: Create new processes asynchronously
- `wait_pid`: Wait for process completion

**Timing:**
- `sleep`: Non-blocking delays

## Error Handling

All operations that can fail include a `context` parameter for error reporting:

```moonbit
///|
test "error handling" {
  with_event_loop(async fn() {
    try {
      let _ = open("/nonexistent/path", flags=0, mode=0o644, context="test operation")
    } catch {
      @os_error.OSError(errno, ..) => {
        println("Operation failed (errno: " + errno.to_string() + ")")
      }
      _ => println("Unknown error occurred")
    }
  })
}
```

## Best Practices

1. **Always use `with_event_loop`** as the entry point for async operations
2. **Properly close file descriptors** using `close_fd` to prevent resource leaks
3. **Use meaningful context strings** for better error diagnostics
4. **Handle errors appropriately** with try-catch blocks
5. **Prefer polling mode** (`can_poll=true`) for network sockets and pipes
6. **Use worker thread mode** (`can_poll=false`) for regular files and blocking operations

```moonbit
///|
test "best practices example" {
  with_event_loop(async fn() {
    let mut fd = -1
    try {
      fd = open("example.txt", flags=0o102, mode=0o644, context="open example file")
      let _ = write(fd, b"data", offset=0, len=4, can_poll=false, context="write to example file")
    } catch {
      err => println("Error: " + err.to_string())
    }
    // Always cleanup resources
    if fd >= 0 {
      close_fd(fd)
    }
  })
}
```

The event loop package provides the foundation for all asynchronous operations in MoonBit's async ecosystem, enabling efficient, scalable, and maintainable asynchronous applications.
