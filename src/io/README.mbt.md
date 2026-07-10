# I/O API (`@moonbitlang/async/io`)

Asynchronous I/O abstraction for MoonBit. This package provides fundamental abstractions for reading from and writing to various data sources, including buffering capabilities, backpressure-aware copies, and helpers that pair naturally with other MoonBit async packages such as `@async`, `@socket`, and `@fs`.

## Table of Contents

- [Quick Start](#quick-start)
- [Core Traits](#core-traits)
  - [Reader Trait](#reader-trait)
  - [Writer Trait](#writer-trait)
  - [Byte and Text Data](#byte-and-text-data)
- [wrap in-memory data into reader](#wrap-in-memory-data-into-reader)
- [Buffered I/O](#buffered-io)
  - [BufferedReader](#bufferedreader)
  - [BufferedWriter](#bufferedwriter)
- [Working with Task Groups and Pipes](#working-with-task-groups-and-pipes)
- [Flow Control & Buffering Strategies](#flow-control--buffering-strategies)
- [Types Reference](#types-reference)
- [Best Practices](#best-practices)

## Quick Start

The fastest way to experiment with `@moonbitlang/async/io` is to couple it with an in-memory pipe and an async task group. The writer task produces bytes, while the reader task consumes them:

```moonbit check
///|
async test "quick start pipeline" {
  @async.with_task_group(root => {
    // Create a pair of connected endpoints that speak the Reader/Writer protocols.
    // Data written to the write end (`writer`) can be read from the read end (`reader`)
    let (reader, writer) = @io.pipe()

    // Spawn a background writer that sends a UTF-8 string in three chunks.
    root.spawn_bg(() => {
      defer writer.close()
      writer.write(b"Hello, ")
      @async.sleep(10)
      writer.write(b"MoonBit")
      @async.sleep(10)
      writer.write(b"!\n")
    })

    // Read everything that arrives and print it as text.
    defer reader.close()
    let message = reader.read_all_text()
    inspect(message, content="Hello, MoonBit!\n")
  })
}
```

This pattern generalises to sockets, files, and any type that implements the `Reader` and `Writer` traits. The following sections dive deeper into the building blocks.

## Core Traits

### Byte and Text Data

I/O streams fundamentally transfer bytes. `Writer::write` accepts a `BytesView`,
which can represent an entire `Bytes` value or a zero-copy slice of one.
`Reader::read_all` returns the raw content as `Bytes`.

Text and JSON conversions are explicit: use `write_text`/`read_all_text` for
UTF-8 text and `write_json`/`read_all_json` for JSON.

```moonbit check
///|
async test "raw bytes" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      // Send raw binary bytes.
      w.write(b"binary data")
    })
    assert_eq(r.read_all(), b"binary data")
  })
}

///|
async test "UTF-8 text" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      w.write_text("Hello, MoonBit!")
    })
    inspect(r.read_all_text(), content="Hello, MoonBit!")
  })
}

///|
async test "JSON" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      // send UTF-8 encoded JSON string
      let data : Json = { "name": "John", "age": 30 }
      w.write_json(data)
    })
    json_inspect(r.read_all_json(), content={ "name": "John", "age": 30 })
  })
}
```

### Reader Trait

The `Reader` trait exposes three complementary levels of granularity:

- `read` performs a best-effort read into an existing buffer and is ideal for incremental protocols. A zero return value indicates EOF.
- `read_exactly` loops until it fills the requested number of bytes or raises `ReaderClosed`, which is helpful when parsing fixed-width frames.
- `read_some` read the next chunk of data once any new data is available
- `read_all` drains the stream into memory and returns the raw `Bytes`.
- `read_all_text` and `read_all_json` drain the stream and decode UTF-8 text or JSON explicitly.
- `read_until` read UTF-8 encoded string from the input until a separator is reached

Each example below shows how a reader pairs with `@io.pipe()` and includes inline comments that highlight the important steps.

```moonbit check
///|
async test "read from reader" {
  @async.with_task_group(root => {
    // Create connected endpoints. `r` is a Reader, `w` is a Writer.
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      // Emit the payload in a single chunk.
      w.write(b"Hello, World!")
    })
    let buf = FixedArray::make(13, b'0')
    // Read up to 13 bytes into the fixed buffer.
    let n = r.read(buf, offset=0, max_len=13)
    inspect(n, content="13")
    // Convert the binary slice to UTF-8 text for inspection.
    inspect(
      @utf8.decode(buf.unsafe_reinterpret_as_bytes()),
      content="Hello, World!",
    )
  })
}

///|
async test "read_exactly - read exact number of bytes" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      // Produce a fixed-size frame.
      w.write(b"0123456789")
    })
    // Blocks until exactly 5 bytes are received or ReaderClosed is raised.
    let data1 = r.read_exactly(5)
    inspect(@utf8.decode(data1), content="01234")
    let data2 = r.read_exactly(5)
    inspect(@utf8.decode(data2), content="56789")
  })
}

///|
async test "read_some - read next chunk of data" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      // the writer supplieds data in two chunks
      w.write_text("abcd")
      @async.sleep(200)
      w.write_text("efgh")
      @async.sleep(200)
      w.write_text("ijkl")
    })
    debug_inspect(
      r.read_some(),
      content=(
        #|Some(<Bytes: [0x61, 0x62, 0x63, 0x64]>)
      ),
    )
    // `read_some` can optionally accept a length limit
    debug_inspect(
      r.read_some(max_len=2),
      content=(
        #|Some(<Bytes: [0x65, 0x66]>)
      ),
    )
    // the amount of data returned may be smaller than `max_len`
    debug_inspect(
      r.read_some(max_len=4),
      content=(
        #|Some(<Bytes: [0x67, 0x68]>)
      ),
    )
    debug_inspect(
      r.read_some(),
      content=(
        #|Some(<Bytes: [0x69, 0x6a, 0x6b, 0x6c]>)
      ),
    )
    // on EOF, `None` is returned
    debug_inspect(r.read_some(), content="None")
  })
}

///|
async test "read_all - read entire content" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      w.write(b"Complete content")
    })
    // `read_all` accumulates everything into raw bytes.
    let data = r.read_all()
    inspect(@utf8.decode(data), content="Complete content")
  })
}

///|
async test "read_all large data" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      // Large payloads can be streamed without precomputing the size.
      w.write(Bytes::make(4097, 0))
    })
    inspect(r.read_all().length(), content="4097")
  })
}

///|
async test "drop - advance stream by discarding data" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      w.write(b"0123456789")
    })
    // Advance the window by five bytes; subsequent reads start after this point.
    // The number of bytes actually dropped would be returned.
    inspect(r.drop(5), content="5")
    let data = r.read_exactly(5)
    inspect(@utf8.decode(data), content="56789")
  })
}

///|
async test "read_until - read text from stream until a separator is found" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      w.write_text("abcd|")
      w.write_text("defg")
    })
    // read until the separator "|" is met. The separator will be consumed as well
    debug_inspect(
      r.read_until("|"),
      content=(
        #|Some("abcd")
      ),
    )
    // .. or read until EOF is reached
    debug_inspect(
      r.read_until("|"),
      content=(
        #|Some("defg")
      ),
    )
    // `None` will be returned when no more data is available
    debug_inspect(r.read_until("|"), content="None")
  })
}

///|
#cfg(target="native")
async test "read_until - used to read file line by line" {
  let file = @fs.open("LICENSE", mode=ReadOnly)
  defer file.close()
  let lines = []
  while file.read_until("\n") is Some(line) {
    // Push each decoded line into a growable array.
    lines.push(line)
  }
  inspect(lines.length(), content="202")
  assert_eq(lines.join("\n") + "\n", @utf8.decode(@fs.read_file("LICENSE")))
}
```

## Wrap In-memory Data Into Reader

`MemoryReader` wraps an async writer callback as a `Reader`. The callback receives an auxiliary writer, runs in the background, and any data written to that writer becomes readable from the `MemoryReader`. This is useful when an API expects a `Reader`, but the data is produced in memory or generated incrementally.

The reader reaches EOF when the callback returns normally. If the callback raises an error, read operations fail with the same error. Closing the reader cancels the background callback if it is still running.

```moonbit check
///|
async test "MemoryReader - generate reader content in memory" {
  let r = @io.MemoryReader() <| w => {
    w.write_text("hello, ")
    @async.sleep(10)
    w.write_text("MoonBit")
  }
  defer r.close()
  inspect(r.read_all_text(), content="hello, MoonBit")
}

///|
async test "MemoryReader - stream generated chunks" {
  let r = @io.MemoryReader() <| w => {
    for part in ["ab", "cd", "ef"] {
      w.write_text(part)
      @async.sleep(10)
    }
  }
  defer r.close()
  debug_inspect(
    r.read_some().map(data => @utf8.decode(data)),
    content=(
      #|Some("ab")
    ),
  )
  debug_inspect(
    r.read_some().map(data => @utf8.decode(data)),
    content=(
      #|Some("cd")
    ),
  )
  debug_inspect(
    r.read_some().map(data => @utf8.decode(data)),
    content=(
      #|Some("ef")
    ),
  )
  debug_inspect(r.read_some(), content="None")
}
```

### Writer Trait

`Writer` focuses on pushing bytes downstream. The three key helpers build on top of the fundamental `write_once` contract:

- `write_once` performs a single best-effort write and returns how many bytes were accepted. Partial writes are allowed, but a non-empty request must accept at least one byte and must never report more than the requested length. End users should not call `write_once` directly in general.
- `write` writes a `BytesView`, repeatedly calling `write_once` until all bytes are written.
- `write_text` UTF-8 encodes a string before writing it, while `write_json` serializes JSON as UTF-8.
- `write_reader` streams from any `Reader`, making it perfect for relaying pipes, sockets, or files without copying into intermediate strings.

The snippets below demonstrate each mode with progressive complexity.

```moonbit check
///|
async test "write to writer" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      // Each call appends to the outgoing stream.
      w.write(b"Hello")
      w.write(b", ")
      w.write(b"World!")
    })
    // `read_all` collapses everything for verification.
    let data = r.read_all()
    inspect(@utf8.decode(data), content="Hello, World!")
  })
}

///|
async test "write_once - single write operation" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      let data : Bytes = b"Test data"
      // Manually call `write_once` to demonstrate partial write accounting.
      let written = w.write_once(data, offset=0, len=data.length())
      inspect(written, content="9")
    })
    let content = r.read_all()
    inspect(@utf8.decode(content), content="Test data")
  })
}

///|
async test "write large data" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    root.spawn_bg(() => {
      defer w.close()
      let data = Bytes::make(1024 * 16, 0)
      // `write` handles chunking internally, avoiding manual loops.
      w.write(data)
    })
    root.spawn_bg(() => {
      defer r.close()
      inspect(r.read_all().length(), content="16384")
    })
  })
}

///|
async test "write_reader - copy from reader to writer" {
  let log = StringBuilder::new()
  @async.with_task_group(root => {
    let (r1, w1) = @io.pipe()
    let (r2, w2) = @io.pipe()
    root.spawn_bg(() => {
      defer r2.close()
      defer w1.close()
      // Stream everything from `r2` into `w1` via `write_reader`.
      w1.write_reader(r2)
    })
    root.spawn_bg(() => {
      defer r1.close()
      while r1.read_some() is Some(data) {
        let data = @utf8.decode(data)
        log.write_string("received \{data}\n")
      }
    })
    root.spawn_bg(() => {
      defer w2.close()
      // Simulate a producer that emits three frames with pauses in between.
      log <+ "sending 4 bytes\n"
      w2.write(b"abcd")
      @async.sleep(300)
      log <+ "sending 4 bytes\n"
      w2.write(b"efgh")
      @async.sleep(300)
      log <+ "sending 4 bytes\n"
      w2.write(b"ijkl")
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|sending 4 bytes
      #|received abcd
      #|sending 4 bytes
      #|received efgh
      #|sending 4 bytes
      #|received ijkl
      #|
    ),
  )
}

///|
async test "write string" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      // Unicode data is transparently encoded via UTF-8.
      w.write_text("abcd中文☺")
    })
    inspect(r.read_all_text(), content="abcd中文☺")
  })
}
```

## Buffered I/O

### BufferedWriter

`BufferedWriter` batches small writes into a fixed-capacity buffer before flushing them to the underlying destination. This greatly reduces syscall overhead and network chatter when dealing with chatty protocols. You can control the buffer size at construction time and decide when to `flush` explicitly—for example before handing the underlying writer to a different subsystem.

```moonbit check
///|
async test "BufferedWriter - basic buffering" {
  let log = StringBuilder::new()
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    root.spawn_bg(() => {
      defer w.close()
      let w = @io.BufferedWriter::new(w, size=4)
      log <+ "2 bytes written\n"
      w.write_text("ab")
      @async.sleep(20)
      log <+ "2 bytes written\n"
      w.write_text("cd")
      @async.sleep(20)
      log <+ "2 bytes written\n"
      w.write_text("ef")
      // Force the remaining bytes out of the buffer.
      w.flush()
    })
    root.spawn_bg(() => {
      defer r.close()
      while r.read_some() is Some(data) {
        log.write_string("received: \{@utf8.decode(data)}\n")
      }
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|2 bytes written
      #|2 bytes written
      #|2 bytes written
      #|received: abcd
      #|received: ef
      #|
    ),
  )
}

///|
async test "BufferedWriter::new with custom size" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      let w = @io.BufferedWriter::new(w, size=8)
      inspect(w.capacity(), content="8")
      // Writes remain buffered until an explicit flush.
      w.write(b"test")
      w.flush()
    })
    let data = r.read_all()
    inspect(@utf8.decode(data), content="test")
  })
}

///|
async test "BufferedWriter::flush - commit buffered data" {
  @async.with_task_group(root => {
    let (r, w) = @io.pipe()
    defer r.close()
    root.spawn_bg(() => {
      defer w.close()
      let w = @io.BufferedWriter::new(w, size=16)
      w.write(b"buffer")
      w.flush()
      // Data written after the flush remains buffered until the next flush.
      w.write(b"more")
      w.flush()
    })
    let data = r.read_all()
    inspect(@utf8.decode(data), content="buffermore")
  })
}

///|
async test "BufferedWriter::write_reader - buffered copy" {
  let log = StringBuilder::new()
  @async.with_task_group(root => {
    let (r1, w1) = @io.pipe()
    let (r2, w2) = @io.pipe()
    root.spawn_bg(() => {
      defer r2.close()
      defer w1.close()
      let w1 = @io.BufferedWriter::new(w1, size=6)
      w1.write_reader(r2)
      // Flush ensures the trailing fragment is committed before closing.
      w1.flush()
    })
    root.spawn_bg(() => {
      defer r1.close()
      while r1.read_some() is Some(data) {
        let data = @utf8.decode(data)
        log.write_string("received \{data}\n")
      }
    })
    root.spawn_bg(() => {
      defer w2.close()
      log <+ "sending 4 bytes\n"
      w2.write(b"abcd")
      @async.sleep(100)
      log <+ "sending 4 bytes\n"
      w2.write(b"efgh")
      @async.sleep(100)
      log <+ "sending 4 bytes\n"
      w2.write(b"ijkl")
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|sending 4 bytes
      #|sending 4 bytes
      #|received abcdef
      #|sending 4 bytes
      #|received ghijkl
      #|
    ),
  )
}
```

## Flow Control & Buffering Strategies

Efficient asynchronous I/O is mostly about balancing throughput and memory usage. Some guiding principles:

- **Prefer streaming copies for large payloads.** `Writer::write_reader` efficiently bridges readers and writers without allocating entire buffers up front.
- **Tune buffer sizes per transport.** A 4 KB buffer is often enough for network sockets, whereas disk-backed streams may benefit from larger chunks. Use `BufferedWriter::new(size=...)` and `BufferedReader::SEGMENT_SIZE` multiples strategically.
- **Avoid a lot of small drops.** `BufferedReader::drop` and `BufferedReader::read` are expensive operations, as they need to copy data when advancing the reader stream. It is recommended to use `op_as_view` to extract data and batch small `read` operations into a single `drop` call at the end when reading multiple small data fragments. `drop` should still be called from time to time, though, to reduce the memory consumption of `BufferedReader`.
- **Flush deliberately.** Frequent flushes lower latency but reduce batching efficiency; schedule them at protocol boundaries (e.g., end of a response frame).

## Types Reference

### Reader

Trait for reading data from a source. Methods include:
- `read(buffer, offset?, max_len?)` - Read data into buffer
- `read_exactly(len)` - Read exact number of bytes
- `read_all()` - Read entire content as raw bytes
- `read_all_text()` - Read entire content as UTF-8 text
- `read_all_json()` - Read and parse UTF-8 encoded JSON

### Writer

Trait for writing data to a destination. Methods include:
- `write_once(data, offset~, len~)` - Single write operation
- `write(data)` - Write a byte view (may require multiple operations)
- `write_text(text)` - UTF-8 encode and write text
- `write_json(value)` - Serialize and write JSON
- `write_reader(reader)` - Copy data from reader to writer

### BufferedReader

A buffered reader that wraps around a normal reader. Methods include:
- `new(reader)` - Create new buffered reader
- `read(buffer, offset?, max_len?)` - Read data
- `read_exactly(len)` - Read exact number of bytes
- `read_all()` - Read entire content
- `op_get(index)` - Access byte by index
- `op_as_view(start?, end~)` - Get slice as view
- `drop(n)` - Drop first n bytes
- `find(target)` - Find substring (raises error if not found)
- `find_opt(target)` - Find substring (returns None if not found)
- `read_line()` - Read line until newline

### MemoryReader

A reader backed by an async in-memory writer callback. Methods include:
- `MemoryReader(callback)` - Create a reader and run `callback` in the background with an auxiliary writer
- `close()` - Close the reader and cancel the background callback if it is still running

### BufferedWriter

A buffered writer with fixed-size buffer. Methods include:
- `new(writer, size?)` - Create new buffered writer
- `capacity()` - Get buffer size
- `flush()` - Commit buffered data
- `write_once(data, offset~, len~)` - Single write operation
- `write(data)` - Write data
- `write_text(text)` - UTF-8 encode and write text
- `write_json(value)` - Serialize and write JSON
- `write_reader(reader)` - Copy from reader

### Encoding

Encoding format for text operations:
- `UTF8` - UTF-8 encoding

### ReaderClosed

Error raised when attempting to read from a closed reader.

## Best Practices

1. **Only one reader/writer at the same time**. Attempting to read from/write to the same reader/writer from multiple tasks easily lead to race condition.
  When multiple readers/writers are needed, it is recommended to adapt the actor pattern by spawning a dedicated reader/writer task and use `@aqueue.Queue` to distribute data atomically.
2. **Use buffered I/O for performance**: Wrap readers and writers with `BufferedReader` and `BufferedWriter` when performing many small reads or writes.
3. **Keep byte and text operations explicit**: Use `read_all()`/`write()` for raw bytes and the text or JSON helpers only when decoding or encoding is intended.

For more examples and detailed usage, explore the test suites in this package—they double as executable documentation.
