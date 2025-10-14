# HTTP server benchmark

This is a benchmark for HTTP server.
The [wrk program](https://github.com/wg/wrk) must be installed to run the benchmark.
You can run the benchmark via:

```
bash examples/http_server_benchmark/bench.sh
```

from project root directory.

Note that the Go server is multicore.
For better comparison, it is run with `GOMAXPROCS=1`,
i.e. limited to a single core.


## Dockerized HTTP Server Benchmark

Note: Just support `linux/amd64` platform now.

1. Build the Docker image:

```bash
bash examples/http_server_benchmark/build.sh
```

2. Then run the benchmark:

```bash
docker run --rm -it http-benchmark:latest
```

And you can run benchmark with Moonbit only:

```bash
docker run --rm -it http-benchmark:latest sh -c 'bash /app/examples/http_server_benchmark/bench.sh --moonbit-only'
```