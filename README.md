# Asynchronous programming library for MoonBit

This library provides basic asynchronous IO functionality for MoonBit,
as well as useful asynchronous programming facilities.
Currently, this library only supports native/LLVM backends on Linux/MacOS.

API document is available at <https://mooncakes.io/docs/moonbitlang/async>.

WARNING: this library is current experimental, API is subjected to future change.

## Features

- [X] TCP/UDP socket
- [X] timer
- [X] pipe
- [ ] asynchronous file system operations
- [X] structured concurrency
- [X] cooperative multi tasking
- [ ] IO worker thread
- [X] Linux support (`epoll`)
- [X] MacOS support (`kqueue`)
- [ ] Windows support
- [ ] WASM backend
- [ ] Javascript backend


## Structured concurrency and error propagation
`moonbitlang/async` features *structured concurrency*.
In `moonbitlang/async`, every asynchronous task must be spawned in a *task group*.
Task groups can be created with the `with_task_group` function

```moonbit
async fn[X] with_task_group(async (TaskGroup) -> X raise) -> X raise
```

When `with_task_group` returns,
it is guaranteed that all tasks spawned in the group already terminate,
leaving no room for orphan task and resource leak.

If any child task in a task group fail with error,
all other tasks in the group will be cancelled.
So there will be no silently ignored error.

For more behavior detail and useful API, consult the API document.

## Task cancellation
In `moonbitlang/async`, all asynchronous operations are by default cancellable.
So no need to worry about accidentally creating uncancellable task.

In `moonbitlang/async`, when a task is cancelled,
it will receive an error at where it suspended.
The cancelled task can then perform cleanup logic using `try .. catch`.
Since most asynchronous operations may throw other error anyway,
correct error handling automatically gives correct cancellation handling,
so most of the time correct cancellation handling just come for free in `moonbitlang/async`.

Currently, it is not allowed to perform other asynchronous operation after a task is cancelled.
Those operations will be cancelled immediately if current task is already cancelled.
Spawn a task in some parent context if asynchronous cleanup is necessary.

## Caveats

Currently, `moonbitlang/async` features a single-threaded, cooperative multitasking model.
With this single-threaded model,
code without suspension point can always be considered atomic.
So no need for expensive lock and less bug.
However, this model also come with some caveats:

- task scheduling can only happen when current task suspend itself,
by performing some asynchronous IO operation or manually calling `@async.pause`.
If you perform heavy computation loop without pausing from time to time,
the whole program will be blocked until the loop terminates,
and other task will not get executed before that.
Similarly, performing blocking IO operation **not** provided by `moonbitlang/async`
may block the whole program as well

- in the same way, task cancellation can only happen when a task is in suspended state
(blocked by IO operation or manually `pause`'ed)

- although internally `moonbitlang/async` may use OS threads to perform some IO job,
user code can only utilize one hardware processor
