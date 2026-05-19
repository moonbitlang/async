# Condition Variable (`@moonbitlang/async/cond_var`)

A condition variable is a **notification primitive**. Tasks call
`wait()` to park themselves; other tasks call `signal()` to wake one
parked task, or `broadcast()` to wake every parked task. Unlike a
`Semaphore`, a `Cond` does **not** count signals — if no task is
parked when you signal, the signal is *lost*. The conventional
mitigation is the predicate-loop idiom described below.

Reach for `Cond` when **N tasks must react to a single event** and
`N` may not be known up front: "config changed, every cache please
reload"; "shutdown requested, every worker pool please drain"; "the
queue went from empty to non-empty, every idle worker please wake."
For point-to-point hand-offs of *values*, prefer `@aqueue.Queue`.
For one-shot one-to-one wakeups or for limiting concurrency, prefer
`@semaphore.Semaphore`.

## Table of Contents

- [The API](#the-api)
- [Signal vs Broadcast](#signal-vs-broadcast)
- [The Lost-Wakeup Trap](#the-lost-wakeup-trap)
- [The Canonical Pattern: Predicate Loop](#the-canonical-pattern-predicate-loop)
- [Pattern: Wake Workers When State Changes](#pattern-wake-workers-when-state-changes)
- [Fairness](#fairness)
- [Cancellation Safety](#cancellation-safety)
- [Choosing Between `Cond`, `Semaphore`, and `Queue`](#choosing-between-cond-semaphore-and-queue)
- [Types Reference](#types-reference)
- [Best Practices](#best-practices)

## The API

- `@cond_var.Cond()` — construct a new condition variable.
- `async Cond::wait(self) -> Unit` — park the current task; resumes
  on `signal`, `broadcast`, or cancellation.
- `Cond::signal(self) -> Unit` — wake one parked waiter (FIFO).
  No-op if no waiter is parked.
- `Cond::broadcast(self) -> Unit` — wake every parked waiter.
  No-op if no waiter is parked.

`signal` and `broadcast` are synchronous; they never block.

## Signal vs Broadcast

`signal()` wakes one waiter (in FIFO order). `broadcast()` wakes all
of them with a single call.

```moonbit check
///|
async test "broadcast wakes every parked waiter" {
  let cond = @cond_var.Cond()
  let log = []
  @async.with_task_group(root => {
    for i in 0..<3 {
      root.spawn_bg(() => {
        cond.wait()
        log.push("waiter \{i}: unblocked")
      })
    }
    @async.sleep(50) // ensure all three are parked
    log.push("broadcast()")
    cond.broadcast()
  })
  json_inspect(log, content=[
    "broadcast()", "waiter 0: unblocked", "waiter 1: unblocked", "waiter 2: unblocked",
  ])
}
```

With `signal()`, only one of the three would have woken. The other
two would stay parked — and because `with_task_group` waits for
every child, the test would hang. Use `signal` only when you know
exactly one waiter should be woken (e.g. a producer handing off to
one of several interchangeable consumers).

## The Lost-Wakeup Trap

`signal()` on an empty waiter queue is a **silent no-op**. If a task
signals before any waiter has parked, the signal disappears, and a
late `wait()` will block indefinitely. The test below demonstrates
the hazard by capping the late wait with `with_timeout`:

```moonbit check
///|
async test "signal before wait is lost" {
  let cond = @cond_var.Cond()
  // Signal first, with no waiters — this signal is dropped.
  cond.signal()
  // Now park; the signal we issued above will not save us.
  let result = try? @async.with_timeout(100, () => cond.wait())
  inspect(result is Err(_), content="true")
}
```

This is *not* a bug in `Cond` — it's the defining property of
condition variables, and it is why the predicate-loop idiom (next
section) is mandatory in real use.

## The Canonical Pattern: Predicate Loop

The rule of thumb: a cond var is a **notification mechanism**, not
the source of truth. The source of truth is a piece of shared state
that the producer mutates and that the consumer can re-check.

```
while !predicate {
  cond.wait()
}
```

The consumer always checks the predicate *before* waiting, so a
producer that fires before the consumer arrives is harmless — the
consumer just sees the predicate already holds and skips `wait()`
entirely. After waking, the consumer re-checks, so a stray wakeup
just costs an extra trip around the loop. There is no ordering you
can construct that loses the event.

```moonbit check
///|
async test "predicate loop handles both orderings" {
  // Case 1: consumer parks first, then producer signals.
  let cond = @cond_var.Cond()
  let mut ready = false
  let log = []
  @async.with_task_group(root => {
    root.spawn_bg(() => {
      while !ready {
        cond.wait()
      }
      log.push("consumer unblocked (parked first)")
    })
    root.spawn_bg(() => {
      @async.sleep(50)
      ready = true
      cond.signal()
    })
  })
  // Case 2: producer fires *before* the consumer arrives.
  let cond2 = @cond_var.Cond()
  let mut ready2 = false
  @async.with_task_group(root => {
    root.spawn_bg(() => {
      ready2 = true
      cond2.signal() // lost — no waiters yet — but the flag is set
    })
    root.spawn_bg(() => {
      @async.sleep(50)
      // The lost signal does not matter: we check the flag first.
      while !ready2 {
        cond2.wait()
      }
      log.push("consumer unblocked (arrived after signal)")
    })
  })
  json_inspect(log, content=[
    "consumer unblocked (parked first)", "consumer unblocked (arrived after signal)",
  ])
}
```

Notice what would have happened if you wrote `cond.wait()` instead
of the `while` loop in Case 2: the lost signal would have left the
consumer parked forever.

## Pattern: Wake Workers When State Changes

A classic use of `broadcast` is "the queue just became non-empty —
all idle workers wake up and try to pull." The producer mutates the
state (here: pushes onto an array) and then signals; the workers
each loop, parking on the cond var when the queue is empty.

```moonbit check
///|
async test "broadcast wakes idle workers when work arrives" {
  let cond = @cond_var.Cond()
  let work : Array[Int] = []
  let received : Array[Array[Int]] = [[], [], []]
  let mut closed = false
  @async.with_task_group(root => {
    for w in 0..<3 {
      root.spawn_bg(() => {
        for ;; {
          // Predicate loop: drain or park.
          while work.is_empty() && !closed {
            cond.wait()
          }
          if work.is_empty() {
            break // queue is empty AND closed
          }
          let item = work.unsafe_pop()
          received[w].push(item)
        }
      })
    }
    // Push five items in three bursts, broadcasting each time.
    @async.sleep(20)
    work.push(10)
    work.push(20)
    cond.broadcast()
    @async.sleep(20)
    work.push(30)
    cond.broadcast()
    @async.sleep(20)
    work.push(40)
    work.push(50)
    cond.broadcast()
    @async.sleep(20)
    // Tell every worker to exit.
    closed = true
    cond.broadcast()
  })
  // Every item was claimed by exactly one worker.
  let total = []
  for arr in received {
    for x in arr {
      total.push(x)
    }
  }
  total.sort()
  json_inspect(total, content=[10, 20, 30, 40, 50])
}
```

A few details worth flagging:

- The predicate checks **both** conditions a worker might be
  waiting for — work to arrive *or* the channel to close. A worker
  that wakes for the wrong reason re-checks and parks again.
- The producer mutates the shared array *first* and then calls
  `broadcast()`. If you call `broadcast()` first and mutate after,
  the woken workers might find the array still empty, park again,
  and miss the update — back to lost-wakeup territory.
- For a real producer/consumer pipeline, `@aqueue.Queue` is
  simpler. Use this lower-level pattern only when you have your own
  shared state that doesn't fit a queue, or when you need to wake
  *all* workers for a non-data event (shutdown, config reload).

## Fairness

When multiple tasks are parked and you call `signal()`, the queue
wakes them in **FIFO** order — the order they called `wait()`.

```moonbit check
///|
async test "signal wakes waiters FIFO" {
  let cond = @cond_var.Cond()
  let log = []
  @async.with_task_group(root => {
    // Task A parks at ~0 ms.
    root.spawn_bg(() => {
      cond.wait()
      log.push("A")
    })
    // Task B parks at ~50 ms.
    root.spawn_bg(() => {
      @async.sleep(50)
      cond.wait()
      log.push("B")
    })
    // Two signals, 50 ms apart.
    @async.sleep(100)
    cond.signal()
    @async.sleep(50)
    cond.signal()
  })
  json_inspect(log, content=["A", "B"])
}
```

## Cancellation Safety

If `signal()` woke a waiter but the waiter is cancelled before it
actually resumes, the wake is preserved (the cancellation is
swallowed for that waiter). A waiter that is cancelled *while still
parked* raises the cancellation error from `wait()` normally — wrap
in `try ... catch` if you need cleanup, or just let the surrounding
`with_task_group` unwind.

```moonbit check
///|
async test "cancellation does not silently consume a wake" {
  let cond = @cond_var.Cond()
  let log = []
  @async.with_task_group(root => {
    let task1 = root.spawn(() => {
      cond.wait()
      log.push("task1 woken")
    })
    root.spawn_bg(() => {
      cond.wait()
      log.push("task2 woken")
    })
    @async.sleep(50)
    cond.signal() // signal handed to task1 (FIFO)
    task1.cancel() // cancel task1 *after* the hand-off
    @async.sleep(50)
    cond.signal() // task2 still needs a wake
  })
  // task1's wake was not silently swallowed by the cancellation —
  // the cancellation was absorbed, and task1 ran normally.
  json_inspect(log, content=["task1 woken", "task2 woken"])
}
```

## Choosing Between `Cond`, `Semaphore`, and `Queue`

| You want… | Use |
|---|---|
| Pass *values* between tasks | `@aqueue.Queue` |
| Limit how many tasks run something | `@semaphore.Semaphore(N)` |
| Wake exactly *one* task on an event | `@semaphore.Semaphore(1, initial_value=0)` (or `Cond.signal` with a predicate) |
| Wake *every* task on an event | **`@cond_var.Cond` with `broadcast()`** |
| Wait for a *predicate* over shared state to hold | **`@cond_var.Cond`** with the `while !predicate` idiom |

`Cond` is the lowest-level of the three. If a queue or semaphore
fits, prefer them — they encode the predicate for you, so you can't
forget the loop. Reach for `Cond` when your "predicate" is custom
shared state.

## Types Reference

### `Cond`

- `Cond::Cond() -> Cond` — construct.
- `async Cond::wait(self) -> Unit` — park; resumes on signal,
  broadcast, or cancellation.
- `Cond::signal(self) -> Unit` — wake one FIFO waiter; no-op if
  none are parked.
- `Cond::broadcast(self) -> Unit` — wake every parked waiter;
  no-op if none are parked.

## Best Practices

1. **Always wait in a loop with a predicate.** Plain `cond.wait()`
   without a re-checked condition is almost always a bug.
2. **Mutate shared state before signaling.** The signal announces
   that the predicate may now hold; the predicate must be true by
   the time waiters check it.
3. **Prefer `broadcast` unless you can prove only one waiter
   matters.** A `signal()` that wakes a waiter who then finds the
   predicate false (and parks again) silently delays every other
   waiter. `broadcast` plus a predicate loop is harder to get wrong.
4. **Prefer `@aqueue.Queue` for value hand-offs.** A queue is a
   cond var plus a buffer plus a predicate, packaged correctly.
5. **Don't share a `Cond` across unrelated predicates.** One cond
   var per logical condition. Mixing them invites lost wakeups for
   one predicate from signals meant for another.
