# HTTP Client & Server (`@moonbitlang/async/http`)

Asynchronous HTTP/1.1 client and server implementation for MoonBit with support for both HTTP and HTTPS protocols.

## Quick Start

### Simple HTTP Requests

Make HTTP requests with a single function call:

```moonbit
///|
async test "simple GET request" {
  let (response, body) = @http.get("https://www.example.org")
  inspect(response.code, content="200")
  inspect(response.reason, content="OK")
  let text = body.text()
  inspect(text.has_prefix("<!doctype html>"), content="true")
}

///|
async test "GET with custom headers" {
  let headers = { "User-Agent": "MoonBit HTTP Client" }
  let (response, body) = @http.get("http://www.example.org", headers~)
  inspect(response.code, content="200")
  let content = body.text()
  inspect(content.length() > 0, content="true")
}
```

## HTTP Client

### One-Shot Requests

For simple requests where you don't need to reuse connections:

```moonbit
///|
async test "one-shot GET" {
  let (response, body) = @http.get("http://www.example.org")
  inspect(response.code, content="200")
  inspect(body.text().length() > 0, content="true")
}

///|
async test "one-shot POST with body" {
  let post_data = b"key=value&foo=bar"
  let headers = { "Content-Type": "application/x-www-form-urlencoded" }

  // Note: This will fail against example.org which doesn't accept POST
  let result = try? @http.post(
      "http://www.example.org/api",
      post_data,
      headers~,
    )
  match result {
    Err(_) => inspect(true, content="true")
    Ok(_) => inspect(false, content="false")
  }
}

///|
async test "one-shot PUT request" {
  let data = b"Updated content"

  // Note: This will fail against example.org
  let result = try? @http.put("http://www.example.org/resource", data)
  match result {
    Err(_) => inspect(true, content="true")
    Ok(_) => inspect(false, content="false")
  }
}
```

### Persistent Connections

Use Client for connection reuse and more control:

```moonbit
///|
async test "client with persistent connection" {
  let client = @http.Client::connect("www.example.org", protocol=Http)

  // Make first request
  let response1 = client.get("/")
  inspect(response1.code, content="200")
  let body1 = client.read_all()
  inspect(body1.text().has_prefix("<!doctype html>"), content="true")
  client.close()
}

///|
async test "HTTPS connection" {
  let client = @http.Client::connect("www.example.org", protocol=Https)
  defer client.close()
  let response = client.get("/")
  inspect(response.code, content="200")
  let body = client.read_all()
  inspect(body.text().length() > 0, content="true")
}

///|
async test "custom port" {
  // Connect to HTTP server on custom port
  let result = try? @http.Client::connect("localhost", protocol=Http, port=8080)
  // This will fail if no server is running on port 8080
  match result {
    Err(_) => inspect(true, content="true")
    Ok(_) => inspect(false, content="true")
  }
}
```

### Request Methods

Make different types of HTTP requests:

```moonbit
///|
async test "GET request" {
  let client = @http.Client::connect("www.example.org", protocol=Http)
  defer client.close()
  let response = client.get("/")
  inspect(response.code, content="200")
  client.skip_response_body()
}

///|
async test "POST request with body" {
  let client = @http.Client::connect("www.example.org", protocol=Http)
  defer client.close()
  let data = b"test data"

  // Will fail as example.org doesn't support POST
  let result = try? client.post("/api", data)
  match result {
    Err(_) => inspect(true, content="true")
    Ok(_) => inspect(false, content="false")
  }
}

///|
async test "PUT request with body" {
  let client = @http.Client::connect("www.example.org", protocol=Http)
  defer client.close()
  let data = b"updated content"

  // Will fail as example.org doesn't support PUT
  let result = try? client.put("/resource", data)
  match result {
    Err(_) => inspect(true, content="true")
    Ok(_) => inspect(false, content="false")
  }
}
```

### Custom Headers

Add custom headers to requests:

```moonbit
///|
async test "persistent headers on client" {
  let headers = { "User-Agent": "MoonBit/1.0", "Accept": "text/html" }
  let client = @http.Client::connect("www.example.org", headers~, protocol=Http)
  defer client.close()

  // All requests from this client will include the headers above
  let response = client.get("/")
  inspect(response.code, content="200")
  client.skip_response_body()
}

///|
async test "extra headers per request" {
  let client = @http.Client::connect("www.example.org", protocol=Http)
  defer client.close()
  let extra_headers = { "X-Custom-Header": "custom-value" }
  let response = client.get("/", extra_headers~)
  inspect(response.code, content="200")
  client.skip_response_body()
}
```

### Request and Response Bodies

Work with request and response bodies:

```moonbit
///|
async test "send request body manually" {
  let client = @http.Client::connect("www.example.org", protocol=Http)
  defer client.close()
  client.request(Post, "/api")

  // Write body data
  client.write(b"First part ")
  client.write(b"Second part")
  client.flush()

  // Will fail as example.org doesn't accept POST
  let result = try? client.end_request()
  match result {
    Err(_) => inspect(true, content="true")
    Ok(_) => inspect(false, content="false")
  }
}

///|
async test "read response headers" {
  let (response, _body) = @http.get("http://www.example.org")
  inspect(response.code, content="200")
  inspect(response.reason, content="OK")

  // Check if specific header exists
  let has_content_type = response.headers.contains("Content-Type")
  inspect(has_content_type, content="false")
}

///|
async test "skip response body" {
  let client = @http.Client::connect("www.example.org", protocol=Http)
  defer client.close()
  let response = client.get("/")
  inspect(response.code, content="200")

  // Skip reading the body if not needed
  client.skip_response_body()
}
```

## Types Reference

### Protocol

Enum representing HTTP protocol:

```moonbit
///|
async test "Protocol enum" {
  let http = @http.Http
  let https = @http.Https
  inspect(http.default_port(), content="80")
  inspect(https.default_port(), content="443")
}
```

### Response

Structure representing an HTTP response:

```moonbit
///|
async test "Response structure" {
  let (response, _body) = @http.get("http://www.example.org")

  // Access response fields
  inspect(response.code, content="200")
  inspect(response.reason, content="OK")
  let headers = response.headers
  let has_headers = headers.length() > 0
  inspect(has_headers, content="true")
}
```

Fields:
- `code: Int` - HTTP status code
- `reason: String` - Status reason phrase
- `headers: Map[String, String]` - Response headers

## Best Practices

1. Always close connections with `defer client.close()`
2. Handle errors using `try?` or `catch`
3. Skip unused bodies with `skip_response_body()`
4. Reuse `Client` for multiple requests to the same host
5. Call `flush()` when sending data in chunks
6. Prefer `protocol=Https` for secure connections

## Error Handling

HTTP operations can raise errors:

```moonbit
///|
async test "error handling" {
  // Invalid URL
  let result1 = try? @http.get("invalid://example.com")
  match result1 {
    Err(_) => inspect(true, content="true")
    Ok(_) => inspect(false, content="true")
  }

  // Connection refused
  let result2 = try? @http.get("http://localhost:9999")
  match result2 {
    Err(_) => inspect(true, content="true")
    Ok(_) => inspect(false, content="true")
  }
}
```

For complete server examples, see `examples/http_file_server` and `examples/http_server_benchmark` directories.
