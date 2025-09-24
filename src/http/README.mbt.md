HTTP support for `moonbitlang/async`.

## Making simple HTTP request

Simple HTTP request can be made in just one line:

```moonbit
///|
async test {
  let (response, body) = @http.get("https://www.example.org")
  inspect(response.code, content="200")
  inspect(body.binary().length(), content="1256")
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
  inspect(body.binary().length(), content="1256")
}
```

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

Here's an example server that returns 404 to every request:

```moonbit
///|
pub async fn server(listen_addr : @socket.Addr) -> Unit {
  @async.with_task_group(fn(group) {
    let server = @socket.TCPServer::new(listen_addr)
    for {
      let (conn, _) = server.accept()
      group.spawn_bg(allow_failure=true, fn() {
        let conn = @http.ServerConnection::new(conn)
        defer conn.close()
        for {
          let request = conn.read_request()
          conn.skip_request_body()
          conn
          ..send_response(404, "NotFound")
          ..write_string("`\{request.path}` not found", encoding=UTF8)
          ..end_response()
        }
      })
    }
  })
}
```
