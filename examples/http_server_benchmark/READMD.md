# HTTP server benchmark

This is a benchmark for HTTP server.
The [wrk program](https://github.com/wg/wrk) must be installed to run the benchmark.
You can run the benchmark via:

```
sh examples/http_server_benchmark/bench.sh
```

from project root directory.

Note that the Go server is multicore.
For better comparison, it is run with `GOMAXPROCS=1`,
i.e. limited to a single core.
