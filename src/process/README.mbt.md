# Process Management (`@moonbitlang/async/process`)

Asynchronous process spawning and management for MoonBit with support for pipes, environment variables, and I/O redirection.

## Quick Start

### Running Simple Commands

Execute commands and collect their output:

```moonbit
///|
#cfg(target="native")
async test "simple command execution" {
  let (exit_code, output) = @process.collect_stdout("echo", ["Hello, World!"])
  inspect(exit_code, content="0")
  let text = output.text()
  inspect(text.has_prefix("Hello"), content="true")
}

///|
#cfg(target="native")
async test "command with exit code" {
  let exit_code = @process.run("sh", ["-c", "exit 42"])
  inspect(exit_code, content="42")
}
```

## Collecting Process Output

### Collect Standard Output

Capture stdout from a process:

```moonbit
///|
#cfg(target="native")
async test "collect stdout" {
  let (code, output) = @process.collect_stdout("printf", ["test output"])
  inspect(code, content="0")
  inspect(output.text(), content="test output")
}

///|
#cfg(target="native")
async test "collect stdout with args" {
  let (code, output) = @process.collect_stdout("sh", [
    "-c", "echo 'line 1'; echo 'line 2'",
  ])
  inspect(code, content="0")
  let text = output.text()
  inspect(text.contains("line 1"), content="true")
  inspect(text.contains("line 2"), content="true")
}
```

### Collect Standard Error

Capture stderr from a process:

```moonbit
///|
#cfg(target="native")
async test "collect stderr" {
  let (code, output) = @process.collect_stderr("sh", [
    "-c", "printf 'error message' >&2",
  ])
  inspect(code, content="0")
  inspect(output.text(), content="error message")
}
```

### Collect Both Stdout and Stderr

Capture both output streams separately:

```moonbit
///|
#cfg(target="native")
async test "collect both streams" {
  let (code, stdout, stderr) = @process.collect_output("sh", [
    "-c", "printf 'out msg'; printf 'err msg' >&2",
  ])
  inspect(code, content="0")
  inspect(stdout.text(), content="out msg")
  inspect(stderr.text(), content="err msg")
}
```

### Collect Merged Output

Merge stdout and stderr into a single stream:

```moonbit
///|
#cfg(target="native")
async test "collect merged output" {
  let (code, output) = @process.collect_output_merged("sh", [
    "-c", "printf 'ab'; printf 'cd' >&2; printf 'ef'",
  ])
  inspect(code, content="0")
  inspect(output.text(), content="abcdef")
}
```

## Process I/O with Pipes

### Reading from Process

Create a pipe to read from a process:

```moonbit
///|
#cfg(target="native")
async test "read from process with pipe" {
  @async.with_task_group(fn(root) {
    let (reader, writer) = @process.read_from_process()
    defer reader.close()
    root.spawn_bg(fn() {
      let _ = @process.run("echo", ["Hello from process"], stdout=writer)

    })
    let output = reader.read_all().text()
    inspect(output.has_prefix("Hello"), content="true")
  })
}
```

### Writing to Process

Create a pipe to write to a process:

```moonbit
///|
#cfg(target="native")
async test "write to process with pipe" {
  @async.with_task_group(fn(root) {
    let (cat_read, we_write) = @process.write_to_process()
    let (we_read, cat_write) = @process.read_from_process()
    root.spawn_bg(fn() {
      let _ = @process.run("cat", ["-"], stdin=cat_read, stdout=cat_write)

    })
    root.spawn_bg(fn() {
      defer we_write.close()
      we_write.write(b"test input\n")
    })
    root.spawn_bg(fn() {
      defer we_read.close()
      let output = we_read.read_all().text()
      inspect(output.contains("test input"), content="true")
    })
  })
}
```

## File Redirection

### Redirect from File

Use a file as process input:

```moonbit
///|
#cfg(target="native")
async test "redirect input from file" {
  @async.with_task_group(fn(root) {
    let input_file = "_build/process_test_input.txt"
    @fs.write_file(input_file, "file content", create=0o644)
    root.add_defer(fn() { @fs.remove(input_file) })
    let (code, output) = @process.collect_stdout(
      "cat",
      [],
      stdin=@process.redirect_from_file(input_file),
    )
    inspect(code, content="0")
    inspect(output.text(), content="file content")
  })
}
```

### Redirect to File

Write process output to a file:

```moonbit
///|
#cfg(target="native")
async test "redirect output to file" {
  @async.with_task_group(fn(root) {
    let output_file = "_build/process_test_output.txt"
    root.add_defer(fn() { @fs.remove(output_file) })
    let code = @process.run(
      "echo",
      ["test output"],
      stdout=@process.redirect_to_file(output_file, create=0o644),
    )
    inspect(code, content="0")
    let content = @fs.read_file(output_file).text()
    inspect(content.has_prefix("test output"), content="true")
  })
}
```

### File to File Redirection

Copy file content using process redirection:

```moonbit
///|
#cfg(target="native")
async test "file to file redirection" {
  @async.with_task_group(fn(root) {
    let input_file = "_build/process_redirect_in.txt"
    let output_file = "_build/process_redirect_out.txt"
    @fs.write_file(input_file, "redirect test", create=0o644)
    root.add_defer(fn() { @fs.remove(input_file) })
    root.add_defer(fn() { @fs.remove(output_file) })
    let _ = @process.run(
      "cat",
      [],
      stdin=@process.redirect_from_file(input_file),
      stdout=@process.redirect_to_file(output_file, create=0o644),
    )
    inspect(@fs.read_file(output_file).text(), content="redirect test")
  })
}
```

## Environment Variables

### Setting Environment Variables

Pass custom environment variables to processes:

```moonbit
///|
#cfg(target="native")
async test "set environment variable" {
  let (code, output) = @process.collect_stdout("sh", ["-c", "echo $MY_VAR"], extra_env={
    "MY_VAR": "my_value",
  })
  inspect(code, content="0")
  inspect(output.text().trim_space(), content="my_value")
}

///|
#cfg(target="native")
async test "multiple environment variables" {
  let (code, output) = @process.collect_stdout(
    "sh",
    ["-c", "echo $VAR1-$VAR2"],
    extra_env={ "VAR1": "first", "VAR2": "second" },
  )
  inspect(code, content="0")
  inspect(output.text().trim_space(), content="first-second")
}
```

### Isolated Environment

Run process without inheriting parent environment:

```moonbit
///|
#cfg(target="native")
async test "isolated environment" {
  let (code, output) = @process.collect_stdout(
    "env",
    [],
    extra_env={ "ONLY_VAR": "only_value" },
    inherit_env=false,
  )
  inspect(code, content="0")
  let text = output.text()
  inspect(text.contains("ONLY_VAR=only_value"), content="true")
  // Parent environment variables won't be present
  inspect(text.contains("PATH="), content="false")
}
```

## Working Directory

### Change Working Directory

Execute processes in a specific directory:

```moonbit
///|
#cfg(target="native")
async test "set working directory" {
  let (code, output) = @process.collect_stdout("pwd", [], cwd="src")
  inspect(code, content="0")
  let text = output.text().trim_space()
  // Check that the path ends with "src" (works across OSes)
  inspect(text.has_suffix("src"), content="true")
}

///|
#cfg(target="native")
async test "relative path in cwd" {
  let (code, output) = @process.collect_stdout("ls", [], cwd="src")
  inspect(code, content="0")
  let text = output.text()
  // Should list contents of src directory
  let has_content = text.length() > 0
  inspect(has_content, content="true")
}
```

## Asynchronous Process Management

### Spawn and Wait

Spawn processes asynchronously and wait for completion:

```moonbit
///|
#cfg(target="native")
async test "spawn and wait" {
  let exit_code = @process.run("sleep", ["0.1"])
  inspect(exit_code, content="0")
}

///|
#cfg(target="native")
async test "wait for specific exit code" {
  let exit_code = @process.run("sh", ["-c", "exit 5"])
  inspect(exit_code, content="5")
}
```

### Spawn Orphan Process

Start a process without blocking:

```moonbit
///|
#cfg(target="native")
async test "spawn orphan and wait later" {
  let pid = @process.spawn_orphan("sh", ["-c", "sleep 0.1; exit 7"])

  // Do other work...
  @async.sleep(50)

  // Wait for the process to complete
  let exit_code = @process.wait_pid(pid)
  inspect(exit_code, content="7")
}
```

## Advanced Usage

### Merge Output Streams

Combine stdout and stderr into one stream:

```moonbit
///|
#cfg(target="native")
async test "merge stdout and stderr" {
  @async.with_task_group(fn(root) {
    let (reader, writer) = @process.read_from_process()
    defer reader.close()
    root.spawn_bg(fn() {
      let _ = @process.run(
        "sh",
        ["-c", "echo 'to stdout'; echo 'to stderr' >&2"],
        stdout=writer,
        stderr=writer,
      )

    })
    let output = reader.read_all().text()
    inspect(output.contains("to stdout"), content="true")
    inspect(output.contains("to stderr"), content="true")
  })
}
```

### Multiple Processes Sharing Output

Run multiple processes writing to the same pipe:

```moonbit
///|
#cfg(target="native")
async test "multiple processes to one pipe" {
  @async.with_task_group(fn(root) {
    let (reader, writer) = @pipe.pipe()
    root.spawn_bg(no_wait=true, fn() {
      defer reader.close()
      let output = reader.read_all().text()
      inspect(output.contains("first"), content="true")
      inspect(output.contains("second"), content="true")
    })
    defer writer.close()
    @async.with_task_group(fn(group) {
      group.spawn_bg(fn() {
        let _ = @process.run("echo", ["first"], stdout=writer)

      })
      group.spawn_bg(fn() {
        let _ = @process.run("echo", ["second"], stdout=writer)

      })
    })
  })
}
```

## Types Reference

### ProcessInput

Trait for types that can be used as process input:

- Created with `write_to_process()` 
- Created with `redirect_from_file(path)`
- Implemented by `@pipe.PipeRead`

### ProcessOutput

Trait for types that can be used as process output:

- Created with `read_from_process()`
- Created with `redirect_to_file(path)`
- Implemented by `@pipe.PipeWrite`

## Best Practices

1. **Always close pipes** with `defer reader.close()` or `defer writer.close()`
2. **Use collect functions** for simple output capture
3. **Use task groups** when managing multiple processes
4. **Handle exit codes** appropriately for error detection
5. **Set working directory** explicitly when path-dependent
6. **Use environment variables** for configuration
7. **Prefer `@process.run`** together with `@async.TaskGroup::spawn`. Only use `spawn_orphan` when necessary.

## Error Handling

Process operations handle errors through exit codes:

```moonbit
///|
#cfg(target="native")
async test "handle process errors" {
  // Non-existent command fails
  let result = try? @process.run("nonexistent_command", [])
  assert_true(result is Err(_))
}

///|
#cfg(target="native")
async test "exit code indicates failure" {
  let exit_code = @process.run("sh", ["-c", "exit 1"])
  let is_failure = exit_code != 0
  inspect(is_failure, content="true")
}
```

For complete examples, see the test files in `src/process/`.
