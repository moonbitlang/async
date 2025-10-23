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

/// HTTP server connection handler for processing client requests.
/// 
/// ServerConnection provides an abstraction for handling HTTP requests and responses
/// over a single TCP connection. It manages the HTTP protocol details while allowing
/// you to focus on application logic.
/// 
/// # Workflow
/// 1. Create a ServerConnection from a TCP connection
/// 2. Read incoming requests with `read_request()`
/// 3. Process request body using the connection as a `@io.Reader`
/// 4. Send response headers with `send_response()`  
/// 5. Write response body using the connection as a `@io.Writer`
/// 6. Complete the response with `end_response()`
/// 7. Repeat for additional requests on the same connection
struct ServerConnection {
  reader : Reader
  conn : @socket.Tcp
  sender : Sender
}

/// Create a new HTTP server connection from an established TCP connection.
/// 
/// This wraps a raw TCP connection with HTTP protocol handling capabilities.
/// The connection can then be used to read HTTP requests and send HTTP responses.
/// 
/// # Parameters
/// - `conn`: An established TCP connection from a client
/// - `headers`: Persistent headers to include in all responses from this connection
/// 
/// # Headers
/// The `headers` parameter allows you to specify headers that will be included
/// in all responses sent through this connection. The following headers are
/// automatically managed and must not be specified:
/// - `Content-Length` - automatically calculated based on response body
/// - `Transfer-Encoding` - managed automatically for chunked encoding
/// 
/// # Example
/// ```moonbit
/// ///|
/// async test {
///   // Create with default headers
///   let tcp_conn = @socket.Tcp::connect_to_host("example.com", port~=80)
///   let server_conn = ServerConnection::new(tcp_conn)
///   server_conn.close()
/// 
///   // Create with custom server headers
///   let headers = Map::from_array([
///     ("Server", "MyApp/1.0"),
///     ("X-Powered-By", "MoonBit")
///   ])
///   let tcp_conn2 = @socket.Tcp::connect_to_host("example.com", port~=80)
///   let server_conn2 = ServerConnection::new(tcp_conn2, headers~)
///   server_conn2.close()
/// }
/// ```
pub fn ServerConnection::new(
  conn : @socket.Tcp,
  headers? : Map[String, String] = {},
) -> ServerConnection {
  { reader: Reader::new(conn), conn, sender: Sender::new(conn, headers~) }
}

/// Close the server connection and release all underlying resources.
/// 
/// This closes the underlying TCP connection. After calling close(), 
/// the connection cannot be used for further requests or responses.
/// Typically this is called automatically by the server framework.
pub fn ServerConnection::close(self : ServerConnection) -> Unit {
  self.conn.close()
}

/// Implementation of `@io.Reader` trait for reading HTTP request bodies.
/// 
/// Allows the server connection to be used anywhere a `@io.Reader` is expected.
/// This reads data from the current request body. If no request is being processed,
/// or the request body has been fully consumed, subsequent reads will block
/// until the next request arrives.
pub impl @io.Reader for ServerConnection with read(
  self,
  buf,
  offset? = 0,
  max_len? = buf.length() - offset,
) {
  self.reader.read(buf, offset~, max_len~)
}

/// Read the next HTTP request from the client.
/// 
/// This method waits for and parses the next HTTP request from the client.
/// It returns the request headers and metadata, while the request body
/// can be read using the ServerConnection as a `@io.Reader`.
/// 
/// If there's an unread request body from the previous request, it will
/// be automatically discarded before reading the new request.
/// 
/// # Returns
/// A `Request` structure containing:
/// - HTTP method (GET, POST, etc.)
/// - Request path
/// - Request headers
/// 
/// # Example
/// ```moonbit
/// ///|
/// async test {
///   let tcp_conn = @socket.Tcp::connect_to_host("example.com", port~=80)
///   let server_conn = ServerConnection::new(tcp_conn)
///   defer server_conn.close()
///   
///   // This would typically be called when a request is received
///   // let request = server_conn.read_request()
///   // println("Method: \{request.meth}, Path: \{request.path}")
/// 
///   // Read request body if needed
///   // if request.meth == Post {
///   //   let body = server_conn.read_all()
///   //   // Process the body...
///   // }
/// }
/// ```
pub async fn ServerConnection::read_request(self : ServerConnection) -> Request {
  self.reader.skip_body()
  self.reader.read_request()
}

/// Skip the current request body without reading it.
/// 
/// This is useful when you don't need to process the request body,
/// such as for GET requests or when rejecting a request early.
/// This is more efficient than reading and discarding the entire body.
/// 
/// # Example
/// ```moonbit
/// ///|
/// async test {
///   let tcp_conn = @socket.Tcp::connect_to_host("example.com", port~=80)
///   let server_conn = ServerConnection::new(tcp_conn)
///   defer server_conn.close()
///   
///   // This would typically be called when processing a request
///   // let request = server_conn.read_request()
///   // if request.path.starts_with("/static/") {
///   //   server_conn.skip_request_body()
///   //   // Send file response...
///   // }
/// }
/// ```
pub async fn ServerConnection::skip_request_body(
  self : ServerConnection,
) -> Unit {
  self.reader.skip_body()
}

/// Implementation of `@io.Writer` trait for writing HTTP response bodies.
/// 
/// Allows the server connection to be used anywhere a `@io.Writer` is expected.
/// This writes data to the current response body being sent. Must be called
/// after `send_response()` and before `end_response()`.
/// 
/// Writing may be buffered - call `flush()` to ensure data is sent immediately.
pub impl @io.Writer for ServerConnection with write_once(
  self,
  buf,
  offset~,
  len~,
) {
  guard self.sender.mode is SendingBody
  self.sender.write_once(buf, offset~, len~)
}

/// Write data from a reader to the current response body.
/// 
/// This is a convenience method that reads all data from the provided
/// reader and writes it to the response body. Useful for streaming large
/// response bodies or forwarding data from files or other sources.
pub impl @io.Writer for ServerConnection with write_reader(self, reader) {
  guard self.sender.mode is SendingBody
  self.sender.write_reader(reader)
}

/// Flush any buffered response body data to the client.
/// 
/// HTTP response body writes may be buffered for performance. This method
/// ensures that all buffered data is sent to the client immediately.
/// This is automatically called by `end_response()`.
pub async fn ServerConnection::flush(self : ServerConnection) -> Unit {
  self.sender.flush()
}

/// Complete the current HTTP response.
/// 
/// This method signals the end of the response body to the client.
/// It must be called after sending all response body data and before
/// processing the next request on the same connection.
/// 
/// # Example
/// ```moonbit
/// ///|
/// async test {
///   let tcp_conn = @socket.Tcp::connect_to_host("example.com", port~=80)
///   let server_conn = ServerConnection::new(tcp_conn)
///   defer server_conn.close()
///   
///   // This demonstrates the complete response flow
///   server_conn.send_response(200, "OK")
///   server_conn.write(b"Hello, World!")
///   server_conn.end_response()  // Required to complete the response
/// }
/// ```
pub async fn ServerConnection::end_response(self : ServerConnection) -> Unit {
  self.sender.end_body()
}

/// Send HTTP response headers to the client.
/// 
/// This initiates an HTTP response by sending the status line and headers.
/// After calling this method, you can write the response body using the
/// ServerConnection as a `@io.Writer`, then complete the response with
/// `end_response()`.
/// 
/// # Parameters
/// - `code`: HTTP status code (e.g., 200, 404, 500)
/// - `reason`: HTTP reason phrase (e.g., "OK", "Not Found", "Internal Server Error")
/// - `extra_headers`: Additional headers for this specific response
/// 
/// # Headers
/// In addition to persistent headers from `ServerConnection::new()`, you can
/// specify additional headers for this response. The following headers are
/// automatically managed and must not be specified:
/// - `Content-Length` - calculated automatically
/// - `Transfer-Encoding` - managed for chunked encoding
/// 
/// # Example
/// ```moonbit
/// ///|
/// async test {
///   let tcp_conn = @socket.Tcp::connect_to_host("example.com", port~=80)
///   let server_conn = ServerConnection::new(tcp_conn)
///   defer server_conn.close()
///   
///   // Simple text response
///   server_conn.send_response(200, "OK")
///   server_conn.write(b"Success!")
///   server_conn.end_response()
/// 
///   // JSON response with custom headers
///   let headers = Map::from_array([
///     ("Content-Type", "application/json"),
///     ("Cache-Control", "no-cache")
///   ])
///   server_conn.send_response(200, "OK", extra_headers=headers)
///   server_conn.write(b"{'status': 'ok'}")
///   server_conn.end_response()
/// }
/// ```
pub async fn ServerConnection::send_response(
  self : ServerConnection,
  code : Int,
  reason : String,
  extra_headers? : Map[String, String] = {},
) -> Unit {
  self.sender.send_response(code, reason, extra_headers~)
}

/// Create and run an HTTP server listening on the specified address.
/// 
/// This is a high-level convenience function that sets up a complete HTTP server.
/// It handles accepting connections, creating ServerConnection instances, and
/// calling your handler function for each client connection.
/// 
/// # Parameters
/// - `addr`: The socket address to listen on
/// - `f`: Handler function called for each client connection
/// - `headers`: Persistent headers included in all responses
/// - `dual_stack`: Whether to enable dual-stack (IPv4/IPv6) listening
/// - `allow_failure`: Whether to ignore failures in the handler function
/// - `max_connections`: Maximum number of concurrent client connections
/// 
/// # Handler Function
/// The handler function receives:
/// - `ServerConnection`: The connection to handle requests/responses
/// - `@socket.Addr`: The client's network address
/// 
/// The connection is automatically closed after the handler returns,
/// so don't call `close()` manually.
/// 
/// # Error Handling
/// If `allow_failure` is true (default), exceptions in the handler function
/// are caught and ignored, allowing the server to continue running.
/// If false, any exception will terminate the server.
/// 
/// # Connection Limits
/// If `max_connections` is specified, the server will accept at most that
/// many concurrent connections. Additional clients will wait until existing
/// connections close.
pub async fn run_server(
  addr : @socket.Addr,
  f : async (ServerConnection, @socket.Addr) -> Unit,
  headers? : Map[String, String],
  dual_stack? : Bool,
  allow_failure? : Bool,
  max_connections? : Int,
) -> Unit {
  @socket.TcpServer::new(addr, dual_stack?).run_forever(
    allow_failure?,
    max_connections?,
    fn(conn, addr) {
      let conn = ServerConnection::new(conn, headers?)
      f(conn, addr)
    },
  )
}
