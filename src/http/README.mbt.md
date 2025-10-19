# HTTP Client and Server API (`@moonbitlang/async/http`)

Asynchronous HTTP client and server implementation for MoonBit. This package provides comprehensive APIs for making HTTP requests, building HTTP servers, and working with HTTP messages.

## Table of Contents

- [Quick Start](#quick-start)
- [HTTP Client](#http-client)
  - [Simple One-time Requests](#simple-one-time-requests)
  - [Reusable Client Connections](#reusable-client-connections)
  - [Request Methods](#request-methods)
  - [Working with Request Bodies](#working-with-request-bodies)
  - [Working with Response Bodies](#working-with-response-bodies)
  - [Custom Headers](#custom-headers)
- [HTTP Server](#http-server)
  - [Basic Server Setup](#basic-server-setup)
  - [Processing Requests](#processing-requests)
  - [Sending Responses](#sending-responses)
  - [Working with Request/Response Bodies](#working-with-requestresponse-bodies)
  - [Server Configuration](#server-configuration)
- [Types Reference](#types-reference)
- [Best Practices](#best-practices)

## Quick Start

Make a simple HTTP request in one line:

```moonbit
///|
async test "quick start example" {
  let (response, body) = @http.get("https://www.example.org")
  inspect(response.code, content="200")
  assert_true(body.text().has_prefix("<!doctype html>"))
}
```

## HTTP Client

### Simple One-time Requests

For simple use cases where you don't need to reuse connections, use the top-level functions:

```moonbit
///|
async test "simple GET request" {
  let (response, body) = @http.get("https://www.example.org")
  inspect(response.code, content="200")
  assert_true(body.text().has_prefix("<!doctype html>"))
}

///|
async test "GET request with custom headers" {
  let headers = { "User-Agent": "MoonBit-HTTP-Client/1.0" }
  let (response, body) = @http.get(
    "https://www.example.org",
    headers=headers,
  )
  inspect(response.code, content="200")
  assert_true(body.text().length() > 0)
}

///|
async test "POST request with body" {
  let (response, _body) = @http.post(
    "https://httpbin.org/post",
    b"test data",
  )
  inspect(response.code, content="200")
}

///|
async test "PUT request with body" {
  let (response, _body) = @http.put(
    "https://httpbin.org/put",
    b"updated data",
  )
  inspect(response.code, content="200")
}
```

### Reusable Client Connections

For better performance when making multiple requests to the same host, use `Client`:

```moonbit
///|
async test "reusable client connection" {
  let client = @http.Client::connect("www.example.org")
  defer client.close()
  
  // First request
  let response1 = client.get("/")
  inspect(response1.code, content="200")
  let body1 = client.read_all()
  assert_true(body1.text().has_prefix("<!doctype html>"))
  
  // Second request on same connection
  let response2 = client.get("/")
  inspect(response2.code, content="200")
  let body2 = client.read_all()
  assert_true(body2.text().has_prefix("<!doctype html>"))
}

///|
async test "client with custom protocol and port" {
  // HTTP (not HTTPS) on custom port
  let client = @http.Client::connect(
    "example.com",
    protocol=Http,
    port=8080,
  )
  defer client.close()
  let response = client.get("/")
  client.skip_response_body()
  inspect(response.code >= 200, content="true")
}

///|
async test "client with persistent headers" {
  let headers = {
    "User-Agent": "MoonBit-Client/1.0",
    "Accept": "application/json",
  }
  let client = @http.Client::connect("www.example.org", headers=headers)
  defer client.close()
  
  // All requests from this client will include these headers
  let response = client.get("/")
  client.skip_response_body()
  inspect(response.code, content="200")
}
```

### Request Methods

The `Client` supports all standard HTTP methods:

```moonbit
///|
async test "various HTTP methods" {
  let client = @http.Client::connect("httpbin.org")
  defer client.close()
  
  // GET request
  let response_get = client.get("/get")
  client.skip_response_body()
  inspect(response_get.code, content="200")
  
  // POST request
  let response_post = client.post("/post", b"data")
  client.skip_response_body()
  inspect(response_post.code, content="200")
  
  // PUT request
  let response_put = client.put("/put", b"updated")
  client.skip_response_body()
  inspect(response_put.code, content="200")
}

///|
async test "generic request method" {
  let client = @http.Client::connect("www.example.org")
  defer client.close()
  
  // For more control, use request() directly
  client.request(Get, "/")
  let response = client.end_request()
  client.skip_response_body()
  inspect(response.code, content="200")
}
```

### Working with Request Bodies

Send request bodies using the client as a `@io.Writer`:

```moonbit
///|
async test "streaming request body" {
  let client = @http.Client::connect("httpbin.org")
  defer client.close()
  
  client.request(Post, "/post")
  
  // Write body in chunks
  client.write(b"part1")
  client.write(b"part2")
  client.flush() // Ensure data is sent
  
  let response = client.end_request()
  client.skip_response_body()
  inspect(response.code, content="200")
}

///|
async test "request with data body" {
  let client = @http.Client::connect("httpbin.org")
  defer client.close()
  
  let data = b"Hello, Server!"
  let response = client.post("/post", data)
  client.skip_response_body()
  inspect(response.code, content="200")
}
```

### Working with Response Bodies

Read response bodies using various methods:

```moonbit
///|
async test "read entire response body" {
  let client = @http.Client::connect("www.example.org")
  defer client.close()
  
  let response = client.get("/")
  inspect(response.code, content="200")
  
  // Read all at once
  let body = client.read_all()
  assert_true(body.text().has_prefix("<!doctype html>"))
}

///|
async test "read response body in chunks" {
  let client = @http.Client::connect("www.example.org")
  defer client.close()
  
  let response = client.get("/")
  inspect(response.code, content="200")
  
  // Read in chunks
  let buf = FixedArray::make(1024, b'\x00')
  let bytes_read = client.read(buf)
  assert_true(bytes_read > 0)
  
  // Skip remaining body
  client.skip_response_body()
}

///|
async test "skip response body" {
  let client = @http.Client::connect("www.example.org")
  defer client.close()
  
  let response = client.get("/")
  inspect(response.code, content="200")
  
  // Skip body if not needed
  client.skip_response_body()
  
  // Can immediately make next request
  let response2 = client.get("/")
  client.skip_response_body()
  inspect(response2.code, content="200")
}
```

### Custom Headers

Add custom headers to requests:

```moonbit
///|
async test "request with extra headers" {
  let client = @http.Client::connect("httpbin.org")
  defer client.close()
  
  let extra_headers = {
    "X-Custom-Header": "custom-value",
    "X-Request-ID": "12345",
  }
  
  let response = client.get("/get", extra_headers=extra_headers)
  client.skip_response_body()
  inspect(response.code, content="200")
}

///|
async test "reading response headers" {
  let client = @http.Client::connect("www.example.org")
  defer client.close()
  
  let response = client.get("/")
  client.skip_response_body()
  
  // Access response headers
  inspect(response.code, content="200")
  inspect(response.reason, content="OK")
  assert_true(response.headers.contains("Content-Type"))
}
```

## HTTP Server

### Basic Server Setup

Create a simple HTTP server using `run_server`:

```moonbit
///|
async test "basic server setup" {
  let server_started : Ref[Bool] = @ref.new(false)
  
  @async.with_task_group(root => {
    // Start server in background
    root.spawn_bg(fn() {
      let addr = @socket.Addr::parse("127.0.0.1:8080")
      server_started.val = true
      
      @http.run_server(addr, fn(conn, _client_addr) {
        conn.read_request() |> ignore
        conn.skip_request_body()
        
        conn
        ..send_response(200, "OK")
        ..write(b"Hello, World!")
        ..end_response()
      })
    })
    
    @async.sleep(100) // Wait for server to start
    assert_true(server_started.val)
  })
}
```

### Processing Requests

Handle incoming HTTP requests:

```moonbit
///|
async test "process different request paths" {
  @async.with_task_group(root => {
    let addr = @socket.Addr::parse("127.0.0.1:8081")
    let server_ready : Ref[Bool] = @ref.new(false)
    
    root.spawn_bg(fn() {
      server_ready.val = true
      @http.run_server(addr, fn(conn, _) {
        conn.read_request() |> ignore
        conn.skip_request_body()
        
        conn
        ..send_response(200, "OK")
        ..write(b"Response sent")
        ..end_response()
      })
    })
    
    @async.sleep(100)
    assert_true(server_ready.val)
  })
}

///|
async test "inspect request method and headers" {
  @async.with_task_group(root => {
    let addr = @socket.Addr::parse("127.0.0.1:8082")
    let processed : Ref[Bool] = @ref.new(false)
    
    root.spawn_bg(fn() {
      @http.run_server(addr, fn(conn, _) {
        let request = conn.read_request()
        conn.skip_request_body()
        
        // Access request properties
        inspect(request.meth == Get, content="true")
        assert_true(request.headers.contains("Host"))
        
        processed.val = true
        
        conn
        ..send_response(200, "OK")
        ..write(b"Request processed")
        ..end_response()
      })
    })
    
    @async.sleep(100)
  })
}
```

### Sending Responses

Send HTTP responses with various status codes:

```moonbit
///|
async test "various response codes" {
  @async.with_task_group(root => {
    let addr = @socket.Addr::parse("127.0.0.1:8083")
    
    root.spawn_bg(fn() {
      @http.run_server(addr, fn(conn, _) {
        conn.read_request() |> ignore
        conn.skip_request_body()
        
        conn
        ..send_response(200, "OK")
        ..write(b"Success")
        ..end_response()
      })
    })
    
    @async.sleep(100)
  })
}

///|
async test "response with custom headers" {
  @async.with_task_group(root => {
    let addr = @socket.Addr::parse("127.0.0.1:8084")
    
    root.spawn_bg(fn() {
      @http.run_server(addr, fn(conn, _) {
        conn.read_request() |> ignore
        conn.skip_request_body()
        
        let extra_headers = {
          "X-Custom-Header": "custom-value",
          "X-Server": "MoonBit",
        }
        
        conn
        ..send_response(200, "OK", extra_headers=extra_headers)
        ..write(b"Response with headers")
        ..end_response()
      })
    })
    
    @async.sleep(100)
  })
}
```

### Working with Request/Response Bodies

Read request bodies and write response bodies:

```moonbit
///|
async test "read request body" {
  @async.with_task_group(root => {
    let addr = @socket.Addr::parse("127.0.0.1:8085")
    
    root.spawn_bg(fn() {
      @http.run_server(addr, fn(conn, _) {
        conn.read_request() |> ignore
        
        // Read entire request body
        let body = conn.read_all()
        body.text() |> ignore
        
        conn
        ..send_response(200, "OK")
        ..write(b"Received: ")
        ..write(body)
        ..end_response()
      })
    })
    
    @async.sleep(100)
  })
}

///|
async test "stream response body" {
  @async.with_task_group(root => {
    let addr = @socket.Addr::parse("127.0.0.1:8086")
    
    root.spawn_bg(fn() {
      @http.run_server(addr, fn(conn, _) {
        conn.read_request() |> ignore
        conn.skip_request_body()
        
        conn.send_response(200, "OK")
        
        // Write response body in chunks
        conn.write(b"Part 1\n")
        conn.write(b"Part 2\n")
        conn.write(b"Part 3\n")
        conn.flush()
        
        conn.end_response()
      })
    })
    
    @async.sleep(100)
  })
}
```

### Server Configuration

Configure server behavior with various options:

```moonbit
///|
async test "server with persistent headers" {
  @async.with_task_group(root => {
    let addr = @socket.Addr::parse("127.0.0.1:8087")
    
    let persistent_headers = {
      "Server": "MoonBit-HTTP/1.0",
      "X-Powered-By": "MoonBit",
    }
    
    root.spawn_bg(fn() {
      @http.run_server(
        addr,
        fn(conn, _) {
          conn.read_request() |> ignore
          conn.skip_request_body()
          
          // Persistent headers are automatically included
          conn
          ..send_response(200, "OK")
          ..write(b"Response with persistent headers")
          ..end_response()
        },
        headers=persistent_headers,
      )
    })
    
    @async.sleep(100)
  })
}

///|
async test "server with max connections" {
  @async.with_task_group(root => {
    let addr = @socket.Addr::parse("127.0.0.1:8088")
    
    root.spawn_bg(fn() {
      // Limit to 10 concurrent connections
      @http.run_server(
        addr,
        fn(conn, _) {
          conn.read_request() |> ignore
          conn.skip_request_body()
          
          conn
          ..send_response(200, "OK")
          ..write(b"Limited connections")
          ..end_response()
        },
        max_connections=10,
      )
    })
    
    @async.sleep(100)
  })
}

///|
async test "server with error handling" {
  @async.with_task_group(root => {
    let addr = @socket.Addr::parse("127.0.0.1:8089")
    
    root.spawn_bg(fn() {
      // Silently ignore handler failures (default is true)
      @http.run_server(
        addr,
        fn(conn, _client_addr) {
          conn.read_request() |> ignore
          conn.skip_request_body()
          
          // If this raises an error, it will be ignored
          conn
          ..send_response(200, "OK")
          ..write(b"Error handling enabled")
          ..end_response()
        },
        allow_failure=true,
      )
    })
    
    @async.sleep(100)
  })
}
```

## Types Reference

### RequestMethod

HTTP request methods:

- `Get` - GET method
- `Head` - HEAD method
- `Post` - POST method
- `Put` - PUT method
- `Delete` - DELETE method
- `Connect` - CONNECT method
- `Options` - OPTIONS method
- `Trace` - TRACE method
- `Patch` - PATCH method

### Request

HTTP request structure:

- `meth : RequestMethod` - HTTP method
- `path : String` - Request path
- `headers : Map[String, String]` - Request headers

### Response

HTTP response structure:

- `code : Int` - HTTP status code
- `reason : String` - Status reason phrase
- `headers : Map[String, String]` - Response headers

### Protocol

HTTP protocol version:

- `Http` - Plain HTTP (default port 80)
- `Https` - HTTP over TLS (default port 443)

### Client

HTTP client for making requests. Methods include:

- `connect()` - Create new client connection
- `close()` - Close connection
- `request()` - Send request header
- `get()`, `post()`, `put()` - Convenience methods
- `end_request()` - Complete request and get response
- `skip_response_body()` - Skip response body
- `flush()` - Flush buffered data
- `read()`, `read_all()` - Read response body (from `@io.Reader`)
- `write()` - Write request body (from `@io.Writer`)

### ServerConnection

HTTP server connection for handling requests. Methods include:

- `new()` - Create from TCP connection
- `close()` - Close connection
- `read_request()` - Read request header
- `skip_request_body()` - Skip request body
- `send_response()` - Send response header
- `end_response()` - Complete response
- `flush()` - Flush buffered data
- `read()`, `read_all()` - Read request body (from `@io.Reader`)
- `write()` - Write response body (from `@io.Writer`)

## Best Practices

1. **Always close clients**: Use `defer client.close()` after connecting
2. **Skip unused bodies**: Call `skip_response_body()` or `skip_request_body()` if not reading the body
3. **Reuse connections**: Use `Client` for multiple requests to the same host
4. **Handle errors gracefully**: Use `allow_failure=true` in servers for robustness
5. **Use persistent headers**: Set common headers in `connect()` or `run_server()` for efficiency
6. **Flush when needed**: Call `flush()` when writing large bodies in chunks
7. **Limit connections**: Use `max_connections` to prevent resource exhaustion
8. **Choose the right tool**: Use simple functions (`get`, `post`) for one-off requests, `Client` for multiple requests
9. **Complete requests properly**: Always call `end_request()` or `end_response()` to complete the transaction
10. **Process bodies appropriately**: Use `read_all()` for small bodies, chunked reading for large bodies

## Error Handling

HTTP operations can raise errors. The package defines:

### HttpProtocolError

- `BadRequest` - Malformed HTTP message
- `HttpVersionNotSupported` - Unsupported HTTP version
- `NotImplemented` - Feature not implemented

### URIParseError

- `InvalidFormat` - Malformed URI
- `UnsupportedProtocol` - Protocol not supported (only `http://` and `https://` are supported)

```moonbit
///|
async test "error handling example" {
  let result = try? @http.get("invalid://example.com")
  inspect(result is Err(_), content="true")
}
```

For more examples and detailed usage, see the test files in this package.
```
