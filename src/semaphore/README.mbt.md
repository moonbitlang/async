# Semaphore (`@moonbitlang/async/semaphore`)

A counting semaphore implementation for MoonBit async operations. Semaphores provide resource counting and access control for concurrent tasks, allowing you to limit the number of tasks that can access a shared resource simultaneously.

## Table of Contents

- [Quick Start](#quick-start)
- [Core Features](#core-features)
- [Usage Examples](#usage-examples)
  - [Mutex Behavior](#mutex-behavior)
  - [Resource Pool](#resource-pool)
  - [Non-blocking Attempts](#non-blocking-attempts)
- [Error Handling and Cancellation](#error-handling-and-cancellation)
- [Best Practices](#best-practices)

## Quick Start

Create a semaphore to limit concurrent access to a shared resource:

```moonbit
///|
async test "basic semaphore usage" {
  let semaphore = @semaphore.Semaphore::new(2) // Allow 2 concurrent accesses
  
  @async.with_task_group(fn(root) {
    for i in 0..<3 {
      root.spawn_bg(fn() {
        semaphore.acquire() // Wait for resource
        println("Task {i} acquired resource")
        @async.sleep(100)
        semaphore.release() // Return resource
      })
    }
  })
}
```

## Core Features

- **Counting semaphore**: Control access to N identical resources
- **Blocking acquisition**: Tasks wait fairly for resource availability 
- **Non-blocking attempts**: Try to acquire without waiting
- **Cancellation support**: Acquire operations can be cancelled/timed out
- **Fair queuing**: Resources are allocated in first-come-first-serve order

## Usage Examples

### Mutex Behavior

Use a semaphore with size 1 to create mutex-like behavior:

```moonbit
///|
async test "semaphore as mutex" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let mutex = @semaphore.Semaphore::new(1)
    
    for i in 0..<3 {
      root.spawn_bg(fn() {
        mutex.acquire()
        log.write_string("task {i} in critical section\\n")
        @async.sleep(200)
        log.write_string("task {i} leaving critical section\\n")
        mutex.release()
      })
    }
  })
  
  // Only one task at a time can be in the critical section
  let output = log.to_string()
  inspect(output.contains("task 0 in critical section"), content="true")
}
```

### Resource Pool

Manage a pool of limited resources (e.g., database connections):

```moonbit
///|
async test "database connection pool" {
  let connection_pool = @semaphore.Semaphore::new(3) // Max 3 connections
  let query_count = @ref.new(0)
  
  @async.with_task_group(fn(root) {
    // Simulate 10 tasks wanting to query the database
    for i in 0..<10 {
      root.spawn_bg(fn() {
        connection_pool.acquire() // Get a connection
        query_count.val += 1
        @async.sleep(50) // Simulate database query
        connection_pool.release() // Return connection to pool
      })
    }
  })
  
  inspect(query_count.val, content="10") // All queries completed
}
```

### Non-blocking Attempts

Sometimes you want to try acquiring a resource without blocking:

```moonbit
///|
test "try_acquire without blocking" {
  let semaphore = @semaphore.Semaphore::new(2, initial_value=1)
  
  // First attempt should succeed
  inspect(semaphore.try_acquire(), content="true")
  
  // Second attempt should fail (no resources left)
  inspect(semaphore.try_acquire(), content="false")
  
  // Release one resource
  semaphore.release()
  
  // Now try_acquire should succeed again
  inspect(semaphore.try_acquire(), content="true")
}
```

### Initial Values

Control how many resources are initially available:

```moonbit
///|
test "custom initial value" {
  // Pool of 5 resources, but start with only 2 available
  let semaphore = @semaphore.Semaphore::new(5, initial_value=2)
  
  inspect(semaphore.try_acquire(), content="true")
  inspect(semaphore.try_acquire(), content="true")
  inspect(semaphore.try_acquire(), content="false") // No more resources
  
  // Release 3 more resources to reach the maximum
  semaphore.release()
  semaphore.release() 
  semaphore.release()
  
  // Now we have 3 available resources
  inspect(semaphore.try_acquire(), content="true")
  inspect(semaphore.try_acquire(), content="true")
  inspect(semaphore.try_acquire(), content="true")
  inspect(semaphore.try_acquire(), content="false")
}
```

## Error Handling and Cancellation

The `acquire` operation can be cancelled, making it suitable for use with timeouts:

```moonbit
///|
async test "semaphore with timeout" {
  let semaphore = @semaphore.Semaphore::new(1)
  
  @async.with_task_group(fn(root) {
    // First task holds the resource for a while
    root.spawn_bg(fn() {
      semaphore.acquire()
      @async.sleep(500)
      semaphore.release()
    })
    
    // Second task tries to acquire with a timeout
    let result = try? @async.with_timeout(100, () => semaphore.acquire())
    inspect(result, content="Err(TimeoutError)")
    
    // After the first task releases, we can acquire
    @async.sleep(500)
    inspect(semaphore.try_acquire(), content="true")
  })
}
```

## Best Practices

- **Always release**: Every successful `acquire()` must be paired with exactly one `release()`
- **Use `defer`**: Consider using `defer semaphore.release()` right after `acquire()` to ensure cleanup
- **Handle cancellation**: Be aware that `acquire()` can be cancelled, potentially leaving resources unreleased
- **Choose appropriate size**: Size your semaphore based on the actual resource limits (CPU cores, network connections, etc.)
- **Prefer `try_acquire`** for non-critical paths where you can handle resource unavailability gracefully

```moonbit
///|
async test "proper resource cleanup" {
  let semaphore = @semaphore.Semaphore::new(1)
  
  semaphore.acquire()
  defer semaphore.release() // Ensures cleanup even if function returns early
  
  // Do work with the protected resource
  @async.sleep(10)
  // Resource is automatically released when function exits
}
```
