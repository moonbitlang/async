# Async Programming Library (`@moonbitlang/async`)

A comprehensive asynchronous programming library for MoonBit that provides structured concurrency, task management, timeouts, and retry mechanisms. This library enables writing efficient concurrent programs with proper error handling and cancellation support.

## Table of Contents

- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
  - [Task Groups](#task-groups)
  - [Individual Tasks](#individual-tasks)
  - [Timeouts](#timeouts)
  - [Retry Mechanisms](#retry-mechanisms)
- [API Reference](#api-reference)
- [Examples](#examples)
- [Best Practices](#best-practices)

## Quick Start

The `async` library is built around structured concurrency using task groups. Here's a simple example that shows how to create concurrent tasks:

```moonbit
///|
async test "basic concurrency" {
  @async.with_task_group(fn(group) {
    // Spawn background tasks
    group.spawn_bg(fn() {
      @async.sleep(100)
      println("Task 1 completed")
    })
    
    group.spawn_bg(fn() {
      @async.sleep(50)
      println("Task 2 completed")
    })
    
    // Main task continues
    println("All tasks spawned")
    @async.sleep(150)
    println("Main task done")
  })
}
```

## Core Concepts

### Task Groups

Task groups implement structured concurrency, ensuring that all child tasks complete before the group exits:

```moonbit
///|
async test "task group basics" {
  let result = @async.with_task_group(fn(group) {
    // All spawned tasks will complete before this group returns
    group.spawn_bg(fn() {
      @async.sleep(100)
    })
    
    42  // Return value from the group
  })
  
  inspect(result, content="42")
}
```

### Individual Tasks

You can spawn tasks that return values and wait for their completion:

```moonbit
///|
async test "task with return value" {
  @async.with_task_group(fn(group) {
    let task = group.spawn(fn() {
      @async.sleep(50)
      "Hello from task!"
    })
    
    let result = task.wait()
    inspect(result, content="Hello from task!")
  })
}
```

### Timeouts

The library provides robust timeout mechanisms:

```moonbit
///|
async test "timeout example" {
  try {
    @async.with_timeout(100, fn() {
      @async.sleep(200)  // This will timeout
    })
  } catch {
    @async.TimeoutError => ()
  }
}

///|
async test "timeout with optional result" {
  let result = @async.with_timeout_opt(100, fn() {
    @async.sleep(200)
    "Won't complete in time"
  })
  
  inspect(result, content="None")
}
```

### Retry Mechanisms

Built-in retry logic with various strategies:

```moonbit
///|
async test "retry with exponential backoff" {
  let mut attempts = 0
  
  let result = @async.retry(
    @async.RetryMethod::ExponentialDelay(initial=10, factor=2.0, maximum=1000),
    max_retry=3,
    fn() {
      attempts += 1
      if attempts < 3 {
        raise @async.TimeoutError()()  // Simulate failure
      }
      "Success on attempt " + attempts.to_string()
    }
  )
  
  inspect(result, content="Success on attempt 3")
}
```

## API Reference

### Task Management

- `with_task_group(f)` - Creates a task group and runs function `f` within it
- `TaskGroup::spawn_bg(f)` - Spawns a background task
- `TaskGroup::spawn(f)` - Spawns a task that returns a value
- `Task::wait()` - Waits for a task to complete and returns its result
- `Task::try_wait()` - Non-blocking check for task completion
- `Task::cancel()` - Cancels a running task

### Timing and Delays

- `sleep(ms)` - Suspends execution for specified milliseconds
- `pause()` - Yields control to allow other tasks to run
- `now()` - Gets current timestamp in milliseconds

### Timeout Operations

- `with_timeout(ms, f)` - Runs function with timeout, raises error on timeout
- `with_timeout_opt(ms, f)` - Runs function with timeout, returns `None` on timeout

### Retry Operations

- `retry(strategy, f)` - Retries function based on specified strategy
- `RetryMethod::Immediate` - Retry immediately on failure
- `RetryMethod::FixedDelay(ms)` - Retry with fixed delay
- `RetryMethod::ExponentialDelay(...)` - Retry with exponential backoff

### Error Handling

- `protect_from_cancel(f)` - Protects function from cancellation
- `TimeoutError` - Error raised when operations time out
- `AlreadyTerminated` - Error when trying to operate on terminated task group

## Examples

### Producer-Consumer Pattern

```moonbit
///|
async test "producer consumer" {
  @async.with_task_group(fn(group) {
    let queue = @async.Queue::new()
    
    // Producer
    group.spawn_bg(fn() {
      for i = 0; i < 5; i = i + 1 {
        queue.put(i)
        @async.sleep(20)
      }
      // Queue operations here
    })
    
    // Consumer
    group.spawn_bg(fn() {
      while true {
        // Process queue items here
      }
    })
  })
}
```

### Parallel Processing with Semaphore

```moonbit
///|
async test "parallel processing" {
  @async.with_task_group(fn(group) {
    let semaphore = @async.Semaphore::new(2)  // Max 2 concurrent tasks
    
    for i = 0; i < 5; i = i + 1 {
      group.spawn_bg(fn() {
        semaphore.acquire()
        defer semaphore.release()
        
        println("Processing item " + i.to_string())
        @async.sleep(100)
        println("Finished item " + i.to_string())
      })
    }
  })
}
```

### Error Propagation and Recovery

```moonbit
///|
async test "error handling" {
  @async.with_task_group(fn(group) {
    // Task that will fail
    group.spawn_bg(allow_failure=true, fn() {
      @async.sleep(50)
      raise @async.TimeoutError()
    })
    
    // Task that succeeds
    group.spawn_bg(fn() {
      @async.sleep(100)
      println("This task completes successfully")
    })
    
    // Main task continues despite failure in background task
    @async.sleep(150)
    ()
  })
}
```

## Best Practices

1. **Use Task Groups**: Always organize concurrent work within task groups for structured concurrency.

2. **Handle Cancellation Properly**: Use `protect_from_cancel` only when absolutely necessary (e.g., critical cleanup operations).

3. **Set Appropriate Timeouts**: Always set timeouts for operations that might hang indefinitely.

4. **Choose the Right Retry Strategy**: 
   - Use `Immediate` for fast-failing operations
   - Use `FixedDelay` for stable retry intervals
   - Use `ExponentialDelay` to avoid overwhelming failing services

5. **Resource Cleanup**: Use `defer` blocks to ensure proper resource cleanup in async contexts.

6. **Error Propagation**: Use `allow_failure=true` when spawning tasks whose failure should not terminate the entire group.

7. **Avoid Blocking Operations**: Use async alternatives for I/O operations to maintain responsiveness.

For more detailed examples and advanced usage patterns, see the individual module documentation and test suites.
