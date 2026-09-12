This is the official async runtime for [MoonBit](docs.moonbitlang.com).

# Overview

This library implements a single threaded asynchronous model,
with structured concurrency API for managing asynchronous tasks.

- scheduler etc. for userland coroutine is in `src/internal/coroutine`.
  Coroutines are all cancellable.
  Cancellation is implemented as a persistent mark on each coroutine.
  Cancelled code will receive a special error on cancellation,
  so that they can run cleanup code on cancellation.
  Swallowing the cancellation signal does not revert the cancelled state of current coroutine,
  and subsequent asynchronous operations will still get cancelled immediately
- event loop for IO etc. is in `src/internal/event_loop`.
  The event loop uses `epoll`/`kqueue`/`IOCP` on Linux/MacOS/Windows,
  Operations that are natively asynchronous, such as socket IO,
  are performed through the event loop directly.
  Blocking operations such as regular file IO are dispatched to a thread pool
- async control flow operations are in `src`.
  The main control flow primitive is structural task group.
  A task group will only terminate after all its children have terminated,
  and will automatically cancel remaining children when necessary.
  See `src/task_group.mbt` for semantic details.

# Socket DNS test troubleshooting

Some agent or sandboxed environments proxy DNS and outbound network access. In
those environments, public hostnames may resolve to addresses in `198.18.0.0/15`
instead of their public IPs. This can make socket hostname tests look wrong even
when the socket implementation is behaving correctly.

Known symptom:

- `src/socket/resolve_host_test.mbt` may report that `mooncakes.io` resolved to a
  `198.18.1.x` address instead of the snapshot value.
- A deliberately invalid hostname may resolve instead of raising, depending on
  the resolver/proxy behavior.

Confirm the resolver behavior directly before changing tests:

```sh
dig +short mooncakes.io
nslookup mooncakes.io
```

If these return `198.18.1.x`, treat the hostname test failure as local
DNS/proxy behavior rather than evidence of a socket implementation bug.

Do not rewrite `resolve_host_test.mbt` to use `localhost` or a protocol mismatch
only to satisfy this kind of local environment. Treat it as an environment issue
unless the same failure reproduces in a normal network environment or CI.

When validating wasm socket work locally, prefer targeted checks first:

```sh
moon check src/socket --target wasm
```

Run socket tests when network behavior is suitable for those tests, and document
DNS/proxy-related failures separately from implementation failures.
