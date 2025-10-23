# Coroutine Package

The `@moonbitlang/async/internal/coroutine` package provides low-level coroutine primitives for the async runtime. This package implements the core functionality for spawning, scheduling, and managing asynchronous coroutines.

## Overview

This package provides the foundation for MoonBit's async/await system, including:

- **Coroutine** - The fundamental unit of async execution
- **Scheduler** - Manages coroutine execution and task queuing
- **Cancellation** - Cooperative cancellation support
- **Suspension** - Primitives for suspending and resuming execution

## Key Types

### Coroutine

The `Coroutine` type represents an async task that can be suspended and resumed:

```moonbit
let coro = spawn(fn() {
  println("Hello from coroutine!")
})
reschedule()
coro.unwrap()
```

### Cancellation

Coroutines support cooperative cancellation:

```moonbit
let coro = spawn(fn() {
  try {
    suspend()  // This will be cancelled
    println("This won't execute")
  } catch {
    Cancelled => println("Coroutine was cancelled")
  }
})
coro.cancel()
reschedule()
```

## Core Functions

### Spawning Coroutines

Use `spawn()` to create new coroutines:

```moonbit
let task = spawn(fn() {
  println("Async task running")
  pause()  // Yield control voluntarily
  println("Task resumed")
})
```

### Scheduling

The scheduler manages coroutine execution:

```moonbit
// Run all ready coroutines
reschedule()

// Check if there are ready tasks
if has_immediately_ready_task() {
  reschedule()
}

// Check if the scheduler has no more work
if no_more_work() {
  println("All tasks completed")
}
```

### Suspension

Coroutines can suspend execution in two ways:

```moonbit
// Voluntary yielding - allows other coroutines to run
pause()

// Blocking suspension - used for I/O operations
suspend()
```

### Protection from Cancellation

Critical sections can be protected from cancellation:

```moonbit
protect_from_cancel(fn() {
  // This code won't be interrupted by cancellation
  println("Critical section")
})
```

## Error Handling

The package defines the `Cancelled` error type for cancellation:

```moonbit
try {
  suspend()
} catch {
  Cancelled => println("Operation was cancelled")
}
```

## Implementation Notes

This is an internal package that provides low-level primitives. Most users should use the higher-level async APIs instead of directly using these coroutine primitives.

The coroutine system uses cooperative scheduling - coroutines must voluntarily yield control through `pause()` or `suspend()` calls.
