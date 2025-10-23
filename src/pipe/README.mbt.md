# Pipe Package

The `@pipe` package provides asynchronous pipe I/O operations for MoonBit, enabling efficient communication between processes and within applications through Unix pipes. This package is part of the MoonBit async ecosystem and integrates seamlessly with the event loop for non-blocking I/O operations.

## Overview

Pipes are a fundamental IPC (Inter-Process Communication) mechanism that allow data to flow from one process to another. This package provides:

- **PipeRead**: The readable end of a pipe supporting async read operations
- **PipeWrite**: The writable end of a pipe supporting async write operations  
- **Standard stream access**: Async-compatible access to stdin, stdout, and stderr
- **Automatic resource management**: Proper cleanup and state restoration

## Key Features

- **Async I/O**: All operations are non-blocking and integrate with the MoonBit event loop
- **Standard streams**: Easy access to stdin, stdout, stderr as async pipes
- **Resource safety**: Automatic cleanup of file descriptors
- **Cross-platform**: Works on Unix-like systems
- **Type safety**: Strongly typed pipe ends prevent misuse

## Basic Usage

### Creating and Using Pipes

```moonbit
async fn example() -> Unit {
  // Create a new pipe
  let (reader, writer) = @pipe.pipe()
  
  // Create a buffer for reading
  let buffer : FixedArray[Byte] = FixedArray::make(1024, 0)
  
  @async.with_task_group(fn(group) {
    // Writer task
    group.spawn_bg(fn() {
      defer writer.close()
      writer.write("Hello, pipe!")
    })
    
    // Reader task  
    group.spawn_bg(fn() {
      defer reader.close()
      let bytes_read = reader.read(buffer)
      ignore(bytes_read)
    })
  })
}
```

### Working with Standard Streams

```moonbit
async fn example_2() -> Unit {
  @async.with_task_group(fn(group) {
    group.spawn_bg(fn() {
      // Write to stdout
      @pipe.stdout.write("Hello, world!\n")
      
      // Write errors to stderr
      @pipe.stderr.write("An error occurred\n")
    })
  })
}
```

### Task-based Communication

```moonbit
async fn example_3() -> Unit {
  @async.with_task_group(fn(group) {
    let (reader, writer) = @pipe.pipe()
    
    // Producer task
    group.spawn_bg(fn() {
      defer writer.close()
      for i = 0; i < 3; i = i + 1 {
        let message = "Message \{i}\n"
        writer.write(message)
        @async.sleep(10)
      }
    })
    
    // Consumer task
    group.spawn_bg(fn() {
      defer reader.close()
      let buffer : FixedArray[Byte] = FixedArray::make(1024, 0)
      while true {
        let n = reader.read(buffer)
        if n == 0 { break } // EOF
        let data = Bytes::from_fixedarray(buffer, len=n)
        let text = @encoding/utf8.decode(data)
        println("Received: \{text}")
      }
    })
  })
}
```

## Advanced Usage

### Reading Exact Amounts

```moonbit
async fn example_4() -> Unit {
  @async.with_task_group(fn(group) {
    let (reader, writer) = @pipe.pipe()
    
    group.spawn_bg(fn() {
      defer writer.close()
      writer.write("Hello, world! This is a test message.")
    })
    
    group.spawn_bg(fn() {
      defer reader.close()
      let first_part = reader.read_exactly(5)
      let decoded = @encoding/utf8.decode(first_part)
      println("First part: \{decoded}")
    })
  })
}
```

## API Reference

### Types

#### `PipeRead`

Represents the readable end of a pipe. Implements the `@io.Reader` trait for async reading operations.

**Methods:**
- `fd() -> Int` - Get the underlying file descriptor
- `close() -> Unit` - Close the pipe end and clean up resources
- `read(buf, offset?, max_len?) -> Int` - Read data into buffer
- `read_exactly(len) -> Bytes` - Read exactly the specified number of bytes
- `read_all() -> Data` - Read all available data

#### `PipeWrite`

Represents the writable end of a pipe. Implements the `@io.Writer` trait for async writing operations.

**Methods:**
- `fd() -> Int` - Get the underlying file descriptor  
- `close() -> Unit` - Close the pipe end and clean up resources
- `write_once(buf, offset, len) -> Int` - Write data from buffer
- `write(data) -> Unit` - Write all data (may require multiple system calls)
- `write_reader(reader) -> Unit` - Copy all data from a reader

### Functions

#### `pipe() -> (PipeRead, PipeWrite) raise`

Create a new pipe using the `pipe(2)` system call. Returns both ends of the pipe, already configured for non-blocking async I/O.

**Returns:** A tuple of `(reader, writer)`
**Raises:** May raise if pipe creation or non-blocking setup fails

### Constants

#### `stdin : PipeRead`

Standard input as an async-compatible pipe reader. Automatically manages blocking mode.

#### `stdout : PipeWrite`

Standard output as an async-compatible pipe writer. Automatically manages blocking mode.

#### `stderr : PipeWrite`  

Standard error as an async-compatible pipe writer. Automatically manages blocking mode.

## Error Handling

The pipe operations integrate with MoonBit's error handling system:

```moonbit
async fn example_5() -> Unit {
  // Pipe creation can raise
  let result = try {
    let (reader, writer) = @pipe.pipe()
    defer { reader.close(); writer.close() }
    (reader, writer)
  } catch {
    err => {
      println("Failed to create pipe: \{err}")
      return
    }
  }
  ignore(result)
}
```

## Best Practices

1. **Always close pipes**: Use `defer` to ensure cleanup
2. **Handle partial operations**: Both reads and writes may be partial
3. **Single reader per pipe**: Only one task should read from a pipe. Use queues for distribution.
4. **Monitor for EOF**: A read returning 0 bytes indicates the write end was closed.
5. **Use standard streams carefully**: The stdin/stdout/stderr constants modify global state.

## Platform Support

This package currently supports Unix-like systems (Linux, macOS, BSD) that provide the `pipe(2)` system call. The implementation uses:

- POSIX pipe operations
- Non-blocking I/O with `O_NONBLOCK`
- File descriptor management through the event loop

## Integration with Async Ecosystem

The pipe package integrates seamlessly with other MoonBit async components:

- **Event Loop**: All I/O operations are event-driven
- **Task Groups**: Perfect for producer-consumer patterns
- **Queues**: Use for multi-consumer scenarios
- **Timers**: Combine with timeouts and delays
- **Other I/O**: Compatible with file, socket, and HTTP operations
