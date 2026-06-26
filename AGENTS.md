# Guidelines for coding agents

## Socket DNS test troubleshooting

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
