# AQueue - Asynchronous Queue

An asynchronous queue implementation for MoonBit that allows readers to wait for data to arrive in a non-blocking manner.

## Overview

The \`@aqueue.Queue\` is a generic asynchronous queue with the following characteristics:

- **Unlimited buffer size**: The internal buffer can grow without bounds
- **Non-blocking writes**: \`put\` operations never block the caller
- **Blocking reads**: \`get\` operations block until data is available
- **Fair scheduling**: Multiple readers are served in first-come-first-serve order
- **Cancellation support**: Blocked readers can be cancelled
- **Try-read option**: \`try_get\` provides non-blocking read alternative

## API Reference

### Queue Creation

\`\`\`moonbit
/// Create a new empty queue
fn init {
  let queue : @aqueue.Queue[Int] = @aqueue.Queue::new()
}
\`\`\`

### Basic Operations

#### put(data: X) -> Unit

Adds an element to the queue. This operation never blocks.

\`\`\`moonbit
fn init {
  let queue : @aqueue.Queue[Int] = @aqueue.Queue::new()
  queue.put(42)
  queue.put(100)
}
\`\`\`

#### get() -> X (async)

Retrieves an element from the queue. Blocks until data is available.

\`\`\`moonbit
async fn consumer() -> Unit {
  let queue : @aqueue.Queue[Int] = @aqueue.Queue::new()
  let value = queue.get() // Blocks until data arrives
  println("Received: \\{value}")
}
\`\`\`

#### try_get() -> X?

Non-blocking variant of \`get\`. Returns \`None\` if queue is empty.

\`\`\`moonbit
test "try_get example" {
  let queue : @aqueue.Queue[Int] = @aqueue.Queue::new()
  inspect(queue.try_get(), content="None")
  queue.put(42)
  inspect(queue.try_get(), content="Some(42)")
  inspect(queue.try_get(), content="None")
}
\`\`\`

## Usage Examples

### Basic Producer-Consumer

\`\`\`moonbit
async test "basic producer consumer" {
  @async.with_task_group(fn(root) {
    let queue : @aqueue.Queue[Int] = @aqueue.Queue::new()
    
    // Producer task
    root.spawn_bg(fn() {
      for i in 0..<5 {
        @async.sleep(100)  // Simulate work
        queue.put(i)
        println("Produced: \\{i}")
      }
    })
    
    // Consumer task
    root.spawn_bg(fn() {
      for _ in 0..<5 {
        let value = queue.get()
        println("Consumed: \\{value}")
      }
    })
  })
}
\`\`\`

### Multiple Consumers

\`\`\`moonbit
async test "multiple consumers" {
  @async.with_task_group(fn(root) {
    let queue : @aqueue.Queue[Int] = @aqueue.Queue::new()
    
    // Consumer 1
    root.spawn_bg(fn() {
      let value = queue.get()
      println("Consumer 1 got: \\{value}")
    })
    
    // Consumer 2  
    root.spawn_bg(fn() {
      let value = queue.get()
      println("Consumer 2 got: \\{value}")
    })
    
    // Producer
    @async.sleep(50)
    queue.put(1)
    queue.put(2)
  })
}
\`\`\`

### Non-blocking Operations

\`\`\`moonbit
test "non-blocking example" {
  let queue : @aqueue.Queue[String] = @aqueue.Queue::new()
  
  // Queue is empty initially
  inspect(queue.try_get(), content="None")
  
  // Add some elements
  queue.put("first")
  queue.put("second")
  
  // Retrieve without blocking
  inspect(queue.try_get(), content="Some(\\"first\\")")
  inspect(queue.try_get(), content="Some(\\"second\\")")
  inspect(queue.try_get(), content="None")
}
\`\`\`

### Cancellation Handling

\`\`\`moonbit
async test "cancellation example" {
  @async.with_task_group(fn(root) {
    let queue : @aqueue.Queue[Int] = @aqueue.Queue::new()
    
    // Consumer with timeout
    @async.with_timeout(200, fn() {
      let value = queue.get() catch {
        err => {
          println("Queue get cancelled: \\{err}")
          raise err
        }
      }
      println("Got: \\{value}")
    }) catch {
      @async.TimeoutError => println("Operation timed out")
      err => raise err
    }
  })
}
\`\`\`

## Key Features

### Fairness

When multiple readers are waiting, they are served in the order they called \`get()\`:

\`\`\`moonbit
async test "fairness demonstration" {
  @async.with_task_group(fn(root) {
    let queue : @aqueue.Queue[Int] = @aqueue.Queue::new()
    
    // Multiple consumers waiting
    root.spawn_bg(fn() {
      let value = queue.get()
      println("First consumer: \\{value}")
    })
    
    root.spawn_bg(fn() {
      let value = queue.get()
      println("Second consumer: \\{value}")
    })
    
    @async.sleep(50)
    queue.put(1)  // Goes to first consumer
    queue.put(2)  // Goes to second consumer
  })
}
\`\`\`

### Memory Efficiency

The queue maintains the invariant that if the buffer is non-empty, there are no waiting readers. This ensures efficient memory usage and prevents unnecessary buffering when consumers are ready.

### Cancellation Safety

Blocked \`get\` operations can be safely cancelled. The queue properly cleans up cancelled readers to prevent resource leaks.

## Best Practices

1. **Use \`try_get\` for polling**: When you don't want to block, use \`try_get\` instead of \`get\`

2. **Handle cancellation**: Always be prepared to handle cancellation in async contexts

3. **Fair resource usage**: The queue serves readers fairly, but producers should be mindful not to overwhelm slow consumers

4. **Error handling**: While \`get\` itself doesn't fail, it can be cancelled, so wrap it in appropriate error handling

## Performance Characteristics

- **put()**: O(1) amortized - never blocks
- **get()**: O(1) when data available, blocks otherwise
- **try_get()**: O(1) - never blocks
- **Memory**: Grows with buffered elements and waiting readers

## Thread Safety

The queue is designed to work safely in MoonBit's async/await environment with proper coroutine scheduling and cancellation support.
