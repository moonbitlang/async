# HTTP Support for MoonBit Async

This package provides comprehensive HTTP client and server functionality for the MoonBit async ecosystem. It supports both HTTP and HTTPS protocols with automatic TLS certificate verification, persistent connections, and efficient streaming of request/response bodies.

## Features

- **HTTP/1.1 protocol support** with keep-alive connections
- **HTTPS with TLS encryption** and certificate verification
- **Streaming request/response bodies** for memory-efficient handling of large data
- **Connection pooling** and reuse for improved performance
- **Comprehensive error handling** with detailed error types
- **High-level convenience functions** for common HTTP operations
- **Low-level API** for advanced use cases requiring fine-grained control

## Quick Start

### Simple HTTP Requests

For simple one-off requests, use the convenience functions:

```moonbit
///|
async test {
  // GET request
  let (response, body) = @http.get("https://www.example.org")
  inspect(response.code, content="200")
  assert_true(body.text().has_prefix("<!doctype html>"))
  
  // POST request with JSON data
  let json_data = b"{'name': 'Alice', 'age': 30}"
  let headers = Map::from_array([("Content-Type", "application/json")])
  let (post_response, _post_body) = @http.post("https://httpbin.org/post", json_data, headers~)
  inspect(post_response.code, content="200")
}
```

### Response Body Processing

The response body supports multiple data formats:

```moonbit
///|
async test {
  let (_, body) = @http.get("https://api.github.com/users/octocat")
  
  // Get as text (UTF-8 decoded)
  let text = body.text()
  println("Response as text: \{text}")
  
  // Parse as JSON
  let json = body.json()
  println("User data: \{json}")
}
```

## HTTP Client

### Basic Client Usage

For more control over requests and connection reuse, use the `Client` type:

```moonbit
///|
async test {
  let client = @http.Client::connect("www.example.org")
  defer client.close()
  
  // Make multiple requests on the same connection
  let response1 = client.get("/")
  inspect(response1.code, content="200")
  let _body1 = client.read_all()
  
  let response2 = client.get("/about")
  inspect(response2.code, content="200")
  let _body2 = client.read_all()
}
```

### Advanced Client Configuration  

```moonbit
///|
async test {
  // Custom headers and HTTP protocol
  let headers = Map::from_array([
    ("User-Agent", "MyApp/1.0"),
    ("Accept", "application/json")
  ])
  
  let client = @http.Client::connect(
    "httpbin.org",
    headers~,
    protocol=Https,
    port=443
  )
  defer client.close()
  
  // These headers will be included in all requests
  let _response = client.get("/get")
  let _data = client.read_all()
}
```

### Streaming Request Bodies

For large request bodies, you can stream data instead of loading it all into memory:

```moonbit
///|
async test {
  let client = @http.Client::connect("httpbin.org")
  defer client.close()
  
  // Start the request
  client.request(Post, "/post")
  
  // Stream data in chunks
  client.write(b"chunk1")
  client.write(b"chunk2")
  client.write(b"chunk3")
  
  // Complete the request and get response
  let response = client.end_request()
  inspect(response.code, content="200")
  let _body = client.read_all()
}
```

## HTTP Server

### Simple Server

Create a basic HTTP server using the high-level `run_server` function:

```moonbit
///|
pub async fn simple_server() -> Unit {
  let addr = @socket.Addr::ipv6(0, 0, 0, 0, 0, 0, 0, 1, 8080)
  
  @http.run_server(addr, fn(conn, _client_addr) {
    for {
      let request = conn.read_request()
      println("\{request.meth} \{request.path}")
      
      // Echo the request path
      conn.send_response(200, "OK")
      conn.write(b"You requested: ")
      conn.write(@encoding/utf8.encode(request.path))
      conn.end_response()
    }
  })
}
```

### Advanced Server with Request Processing

```moonbit
///|
pub async fn api_server() -> Unit {
  let addr = @socket.Addr::ipv6(0, 0, 0, 0, 0, 0, 0, 0, 8080)
  
  // Server headers included in all responses
  let server_headers = Map::from_array([
    ("Server", "MoonBit-HTTP/1.0"),
    ("X-Powered-By", "MoonBit")
  ])
  
  @http.run_server(addr, fn(conn, _client_addr) {
    for {
      let request = conn.read_request()
      
      match request.path {
        "/api/health" => {
          conn.skip_request_body()
          
          let headers = Map::from_array([("Content-Type", "application/json")])
          conn.send_response(200, "OK", extra_headers=headers)
          conn.write(b"{'status': 'healthy', 'timestamp': '2024-01-01T00:00:00Z'}")
          conn.end_response()
        }
        "/api/echo" => {
          let body = conn.read_all()
          
          conn.send_response(200, "OK")
          conn.write(b"Echo: ")
          conn.write(body)
          conn.end_response()
        }
        _ => {
          conn.skip_request_body()
          
          conn.send_response(404, "Not Found")
          conn.write(b"Endpoint not found: ")
          conn.write(@encoding/utf8.encode(request.path))
          conn.end_response()
        }
      }
    }
  }, headers=server_headers)
}
```

## Error Handling

The HTTP package provides comprehensive error types for different failure scenarios:

```moonbit
///|
async test {
  // Handle URI parsing errors
  try {
    let (_, _) = @http.get("invalid-uri")
  } catch {
    @http.URIParseError::InvalidFormat => println("Invalid URI format")
    @http.URIParseError::UnsupportedProtocol(protocol) => 
      println("Unsupported protocol: \{protocol}")
  }
  
  // Handle HTTP protocol errors  
  try {
    let client = @http.Client::connect("httpbin.org")
    defer client.close()
    let _response = client.get("/get")
    let _body = client.read_all()
  } catch {
    @http.HttpProtocolError::BadRequest => println("Malformed HTTP message")
    @http.HttpProtocolError::HttpVersionNotSupported(version) => 
      println("Unsupported HTTP version: \{version}")
    @http.HttpProtocolError::NotImplemented => 
      println("HTTP feature not implemented")
  }
}
```

## Protocol Support

### HTTP vs HTTPS

```moonbit
///|
async test {
  // HTTPS (default) - secure with certificate verification
  let https_client = @http.Client::connect("httpbin.org")
  defer https_client.close()
  
  // HTTP - plain text for development or internal services
  let http_client = @http.Client::connect(
    "httpbin.org",
    protocol=Http,
    port=80
  )
  defer http_client.close()
}
```

### Custom Ports

```moonbit
///|
async test {
  // Connect to non-standard ports
  let client = @http.Client::connect(
    "httpbin.org",
    protocol=Https,
    port=443
  )
  defer client.close()
  
  // Default ports are used if not specified:
  // - HTTP: port 80
  // - HTTPS: port 443
}
```

## Best Practices

### Connection Management

```moonbit
///|
async test {
  // Always close clients to free resources
  let client = @http.Client::connect("httpbin.org")
  defer client.close()  // Recommended: use defer for cleanup
  
  // Reuse connections for multiple requests
  let _response1 = client.get("/get")
  let _body1 = client.read_all()
  
  let _response2 = client.get("/json")
  let _body2 = client.read_all()
}
```

### Response Body Handling

```moonbit
///|
async test {
  let client = @http.Client::connect("httpbin.org")
  defer client.close()
  
  let response = client.get("/json")
  
  if response.code == 200 {
    // Always consume or skip the response body
    let body = client.read_all()
    println("Success: \{body.text()}")
  } else {
    // Skip unwanted response bodies
    client.skip_response_body()
    println("Request failed with status: \{response.code}")
  }
}
```

### Server Resource Management

```moonbit
///|
pub async fn robust_server() -> Unit {
  let addr = @socket.Addr::ipv6(0, 0, 0, 0, 0, 0, 0, 0, 8080)
  
  @http.run_server(
    addr,
    fn(conn, _client_addr) {
      // Handle requests in a loop
      for {
        let request = conn.read_request()
        
        // Always handle the request body appropriately
        match request.meth {
          Get | Head => conn.skip_request_body()
          Post | Put | Patch => {
            let _body = conn.read_all()
            // Process body data...
          }
          _ => conn.skip_request_body()
        }
        
        // Always send a complete response
        conn.send_response(200, "OK")
        conn.write(b"Response data")
        conn.end_response()  // Required!
      }
    },
    allow_failure=true,      // Continue on handler errors
    max_connections=100      // Limit concurrent connections
  )
}
```
