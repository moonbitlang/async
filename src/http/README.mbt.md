HTTP support for `moonbitlang/async`.

## Making simple HTTP request

Simple HTTP request can be made in just one line:

```moonbit
///|
async test {
  let (response, body) = @http.get("https://www.example.org")
  inspect(response.code, content="200")
  assert_true(body.text().has_prefix("<!doctype html>"))
}
```

You can use use `body.text()` to get a `String` (decoded via UTF8)
or `body.json()` for a `Json` from the response body.

## Generic HTTP client
Sometimes, the simple one-time `@http.get` etc. is insufficient,
for example you need to reuse the same connection for multiple requests,
or the request/response body is very large and need to be processed lazily.
In this case, you can use the `@http.Client` type.
`@http.Client` can be created via `@http.Client::connect(hostname)`,
by default `https` is used, this can be overriden using the `protocol` parameter.

The workflow of performing a request with `@http.Client` is:

1. initiate the request via `client.request(..)`
1. send the request body by using `@http.Client` as a `@io.Writer`
1. complete the request and obtain response header from the server
  via `client.end_request()`
1. read the response body by using `@http.Client` as a `@io.Reader`,
  or use `client.read_all()` to obtain the whole response body.
  Yon can also ignore the body via `client.skip_response_body()`

The helpers `client.get(..)`, `client.put(..)` etc.
can be used to perform step (1)-(3) above.

A complete example:

```moonbit
///|
async test {
  let client = @http.Client::connect("www.example.org")
  defer client.close()
  let response = client..request(Get, "/").end_request()
  inspect(response.code, content="200")
  let body = client.read_all()
  assert_true(body.text().has_prefix("<!doctype html>"))
}
```

## Using HTTP Proxy

The HTTP client supports routing requests through HTTP proxies using the CONNECT method.
Both HTTP and HTTPS target servers are supported through the proxy.

Create a proxy configuration:

`let proxy = @http.Proxy::all("proxy.example.com", port=8080)` - for all protocols

`let proxy = @http.Proxy::http("proxy.example.com", port=8080)` - HTTP only

`let proxy = @http.Proxy::https("proxy.example.com", port=8080)` - HTTPS only

`let proxy = @http.Proxy::custom("http-proxy.com", http_port=8080, "https-proxy.com", https_port=8443)` - different proxies

Use it with simple HTTP requests:

`let (response, body) = @http.get("http://www.example.org", proxy~)`

Or with a persistent client connection:

`let client = @http.Client::connect("www.example.org", protocol=@http.Http, proxy~)`

## Writing HTTP servers
The `@http.ServerConnection` type provides abstraction for a connection in a HTTP server.
It can be created via `@http.ServerConnection::new(tcp_connection)`.
The workflow of processing a request via `@http.ServerConnection` is:

1. use `server.read_request()` to wait for incoming request
  and obtain the header of the request
1. read the request body by usign `@http.ServerConnection` as a `@io.Reader`.
  or use `server.read_all()` to obtain the whole request body.
  Yon can also ignore the body via `server.skip_request_body()`
1. use `server.send_response` to initiate a response and send the response header
1. send response body by using `@http.ServerConnection` as a `@io.Writer`
1. call `server.end_response()` to complete the response

The `@http` package also provides a helper `@http.run_server`
for setting up and running a HTTP server directly.
It accepts a callback function for handling connection,
the callback will receive a `@http.ServerConnection` and the address of client.
Here's an example server that returns 404 to every request:

```moonbit
///|
pub async fn server(listen_addr : @socket.Addr) -> Unit {
  @http.run_server(listen_addr, fn(conn, _) {
    for {
      let request = conn.read_request()
      conn.skip_request_body()
      conn
      ..send_response(404, "NotFound")
      ..write("`\{request.path}` not found")
      ..end_response()
    }
  })
}
```
