// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// HTTP client for making requests to a remote server.
/// 
/// The Client provides a persistent connection to a server and supports
/// connection reuse across multiple requests. It handles both HTTP and HTTPS
/// protocols with automatic TLS certificate verification for secure connections.
/// 
/// # Workflow
/// 1. Create a client with `Client::connect()`
/// 2. Make requests using `request()` followed by writing body data
/// 3. Complete requests with `end_request()` to get the response
/// 4. Read response body using the client as a `@io.Reader`
/// 5. Close the client with `close()` when done
struct Client {
  reader : Reader
  conn : @socket.Tcp
  tls : @tls.Tls?
  sender : Sender
}

/// Create a new HTTP client by connecting to a remote host.
/// 
/// Establishes a connection to the specified host and port. For HTTPS connections,
/// a TLS handshake is performed and the server certificate is verified.
/// 
/// # Parameters
/// - `host`: The hostname or IP address to connect to
/// - `headers`: Persistent headers to include in all requests from this client
/// - `protocol`: HTTP or HTTPS protocol (defaults to HTTPS for security)
/// - `port`: Port number to connect to (defaults to protocol standard port)
/// 
/// # Headers
/// The `headers` parameter allows you to specify headers that will be included
/// in all requests made by this client. The following headers are automatically
/// managed and must not be specified:
/// - `Host` - automatically set to the target hostname  
/// - `Content-Length` - automatically calculated based on request body
/// - `Transfer-Encoding` - managed automatically for chunked encoding
/// 
/// # Example
/// ```moonbit
/// ///|
/// async test {
///   // Connect with default HTTPS
///   let client = @http.Client::connect("api.github.com")
///   defer client.close()
/// 
///   // Connect with custom headers and HTTP
///   let headers = Map::from_array([("User-Agent", "MyApp/1.0")])
///   let client2 = @http.Client::connect(
///     "example.com", 
///     headers~, 
///     protocol=Http, 
///     port=8080
///   )
///   defer client2.close()
/// }
/// ```
pub async fn Client::connect(
  host : String,
  headers? : Map[String, String] = {},
  protocol? : Protocol = Https,
  port? : Int = protocol.default_port(),
) -> Client {
  let conn = @socket.Tcp::connect_to_host(host, port~)
  let tls = match protocol {
    Http => None
    Https => Some(@tls.Tls::client(conn, host~))
  }
  let reader = match tls {
    None => Reader::new(conn)
    Some(tls) => Reader::new(tls)
  }
  headers["Host"] = host
  let sender = match tls {
    None => Sender::new(conn, headers~)
    Some(tls) => Sender::new(tls, headers~)
  }
  { conn, tls, reader, sender }
}

/// Close the HTTP client and release all underlying resources.
/// 
/// This closes the TCP connection and any associated TLS session.
/// After calling close(), the client cannot be used for further requests.
/// It's recommended to use `defer client.close()` to ensure cleanup.
pub fn Client::close(self : Client) -> Unit {
  if self.tls is Some(tls) {
    tls.close()
  }
  self.conn.close()
}

/// Implementation of `@io.Reader` trait for reading HTTP response bodies.
/// 
/// Allows the client to be used anywhere a `@io.Reader` is expected.
/// This reads data from the current response body. If no response is being
/// read, or the response body has been fully consumed, this will block
/// until the next response becomes available.
pub impl @io.Reader for Client with read(
  self,
  buf,
  offset? = 0,
  max_len? = buf.length() - offset,
) {
  self.reader.read(buf, offset~, max_len~)
}

/// Implementation of `@io.Writer` trait for writing HTTP request bodies.
/// 
/// Allows the client to be used anywhere a `@io.Writer` is expected. 
/// This writes data to the current request body being sent. Must be called
/// after `request()` and before `end_request()`.
/// 
/// Writing may be buffered - call `flush()` to ensure data is sent immediately.
pub impl @io.Writer for Client with write_once(self, buf, offset~, len~) {
  guard self.sender.mode is SendingBody
  self.sender.write_once(buf, offset~, len~)
}

/// Write data from a reader to the current request body.
/// 
/// This is a convenience method that reads all data from the provided
/// reader and writes it to the request body. Useful for streaming large
/// request bodies or forwarding data from other sources.
pub impl @io.Writer for Client with write_reader(self, reader) {
  guard self.sender.mode is SendingBody
  self.sender.write_reader(reader)
}

/// Flush any buffered request body data to the server.
/// 
/// HTTP request body writes may be buffered for performance. This method
/// ensures that all buffered data is sent to the server immediately.
/// This is automatically called by `end_request()`.
pub async fn Client::flush(self : Client) -> Unit {
  self.sender.flush()
}

/// Complete the current request and receive the response headers.
/// 
/// This method:
/// 1. Sends any remaining buffered request body data
/// 2. Signals the end of the request body to the server  
/// 3. Waits for and parses the HTTP response headers
/// 4. Returns the response metadata (status code, headers, etc.)
/// 
/// After calling this method, the response body can be read using the
/// client as a `@io.Reader`. The response body must be fully consumed
/// (or skipped with `skip_response_body()`) before making the next request.
/// 
/// # Example
/// ```moonbit
/// ///|
/// async test {
///   let client = @http.Client::connect("example.com")
///   defer client.close()
///   
///   client.request(Get, "/api/data")
///   // No request body for GET, so end immediately
///   let response = client.end_request()
///   println("Status: \{response.code}")
///   let _body = client.read_all()
/// }
/// ```
pub async fn Client::end_request(self : Client) -> Response {
  self.sender.end_body()
  self.reader.skip_body()
  self.reader.read_response()
}

/// Initiate an HTTP request with the specified method and path.
/// 
/// This sends the HTTP request line and headers to the server, but does not
/// send the request body. After calling this method:
/// - Write the request body using the client as a `@io.Writer`
/// - Call `end_request()` to complete the request and get the response
/// 
/// # Parameters
/// - `meth`: The HTTP method (GET, POST, PUT, etc.)
/// - `path`: The request path (e.g., "/api/users")
/// - `extra_headers`: Additional headers for this specific request
/// 
/// # Headers
/// In addition to persistent headers from `Client::connect()`, you can specify
/// additional headers for this request. The following headers are automatically
/// managed and must not be specified:
/// - `Host` - set during client connection
/// - `Content-Length` - calculated automatically  
/// - `Transfer-Encoding` - managed for chunked encoding
/// 
/// # Example
/// ```moonbit
/// ///|
/// async test {
///   let client = @http.Client::connect("example.com")
///   defer client.close()
///   
///   // Simple GET request
///   client.request(Get, "/users/123")
///   let _response = client.end_request()
/// 
///   // POST with custom headers
///   let headers = Map::from_array([("Content-Type", "application/json")])
///   client.request(Post, "/users", extra_headers=headers)
///   client.write(b"{'name': 'Alice'}")
///   let _response2 = client.end_request()
/// }
/// ```
pub async fn Client::request(
  self : Client,
  meth : RequestMethod,
  path : String,
  extra_headers? : Map[String, String] = {},
) -> Unit {
  self.sender.send_request(meth, path, extra_headers~)
}

/// Skip the current response body without reading it.
/// 
/// This is useful when you only care about response headers and status code,
/// not the body content. After calling this method, you can immediately
/// make the next request without reading the response body.
/// 
/// This is more efficient than reading and discarding the entire response body.
pub async fn Client::skip_response_body(self : Client) -> Unit {
  self.reader.skip_body()
}

/// Perform a complete GET request in one call.
/// 
/// This is a convenience method that combines `request()`, optional body writing,
/// and `end_request()` into a single call. Use this for simple GET requests
/// where you want the response immediately.
/// 
/// # Parameters  
/// - `path`: The request path
/// - `extra_headers`: Additional headers for this request
/// - `body`: Optional request body (unusual for GET, but allowed)
/// 
/// # Example
/// ```moonbit
/// ///|
/// async test {
///   let client = @http.Client::connect("example.com")
///   defer client.close()
///   
///   let response = client.get("/api/users")
///   println("Users: \{client.read_all().text()}")
/// }
/// ```
pub async fn Client::get(
  self : Client,
  path : String,
  extra_headers? : Map[String, String] = {},
  body? : &@io.Data,
) -> Response {
  self.request(Get, path, extra_headers~)
  if body is Some(body) {
    self.write(body)
  }
  self.end_request()
}

/// Perform a complete PUT request in one call.
/// 
/// This is a convenience method that combines `request()`, body writing,
/// and `end_request()` into a single call. Use this for simple PUT requests
/// where you have the entire request body available.
/// 
/// # Parameters
/// - `path`: The request path  
/// - `body`: The request body data
/// - `extra_headers`: Additional headers for this request
/// 
/// # Example
/// ```moonbit
/// ///|
/// async test {
///   let client = @http.Client::connect("example.com")
///   defer client.close()
///   
///   let data = b"{'name': 'Bob', 'age': 25}"
///   let headers = Map::from_array([("Content-Type", "application/json")])
///   let _response = client.put("/api/users/456", data, extra_headers=headers)
/// }
/// ```
pub async fn Client::put(
  self : Client,
  path : String,
  body : &@io.Data,
  extra_headers? : Map[String, String] = {},
) -> Response {
  self..request(Put, path, extra_headers~)..write(body).end_request()
}

/// Perform a complete POST request in one call.
/// 
/// This is a convenience method that combines `request()`, body writing,
/// and `end_request()` into a single call. Use this for simple POST requests
/// where you have the entire request body available.
/// 
/// # Parameters
/// - `path`: The request path
/// - `body`: The request body data  
/// - `extra_headers`: Additional headers for this request
/// 
/// # Example
/// ```moonbit
/// ///|
/// async test {
///   let client = @http.Client::connect("example.com")
///   defer client.close()
///   
///   let form_data = b"username=alice&email=alice@example.com"
///   let headers = Map::from_array([("Content-Type", "application/x-www-form-urlencoded")])
///   let _response = client.post("/register", form_data, extra_headers=headers)
/// }
/// ```
pub async fn Client::post(
  self : Client,
  path : String,
  body : &@io.Data,
  extra_headers? : Map[String, String] = {},
) -> Response {
  self..request(Post, path, extra_headers~)..write(body).end_request()
}
