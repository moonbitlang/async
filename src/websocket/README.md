# WebSocket API for MoonBit Async Library

This module provides a complete WebSocket implementation for the MoonBit async library, supporting both client and server functionality.

## Features

- **WebSocket Server**: Accept WebSocket connections with HTTP upgrade handshake
- **WebSocket Client**: Connect to WebSocket servers
- **Message Types**: Support for text and binary messages
- **Frame Management**: Automatic frame assembly/disassembly
- **Control Frames**: Built-in ping/pong and close frame handling
- **Masking**: Proper client-side masking for frame payloads
- **Error Handling**: Comprehensive error types for WebSocket protocol

## Quick Start

### WebSocket Server

```moonbit
import "moonbitlang/async/websocket" as websocket
import "moonbitlang/async/socket" as socket

// Create a simple echo server
async fn start_server() -> Unit {
  websocket.run_server(
    socket.Addr::parse("127.0.0.1:8080"),
    "/ws",
    async fn(ws, client_addr) raise {
      println("New connection from \{client_addr}")
      
      for {
        let msg = ws.receive()
        match msg.mtype {
          websocket.MessageType::Text => {
            let text = @encoding/utf8.decode(msg.data)
            ws.send_text("Echo: " + text)
          }
          websocket.MessageType::Binary => {
            ws.send_binary(msg.data)
          }
        }
      }
    },
    allow_failure=true,
  )
}
```

### WebSocket Client

```moonbit
// Connect to a WebSocket server
async fn client_example() -> Unit {
  let client = websocket.Client::connect("localhost", "/ws", port=8080)
  
  // Send a message
  client.send_text("Hello, WebSocket!")
  
  // Receive a response
  let response = client.receive()
  match response.mtype {
    websocket.MessageType::Text => {
      let text = @encoding/utf8.decode(response.data)
      println("Received: \{text}")
    }
    websocket.MessageType::Binary => {
      println("Received binary data")
    }
  }
  
  client.close()
}
```

## API Reference

### Server Types

#### `ServerConnection`
Represents a WebSocket connection on the server side.

**Methods:**
- `send_text(text: String)` - Send a text message
- `send_binary(data: Bytes)` - Send binary data
- `receive() -> Message` - Receive a message (blocks until message arrives)
- `ping(data?: Bytes)` - Send a ping frame
- `pong(data?: Bytes)` - Send a pong frame  
- `send_close(code?: CloseCode, reason?: String)` - Send close frame
- `close()` - Close the connection

#### `run_server` Function
Start a WebSocket server.

```moonbit
async fn run_server(
  addr: socket.Addr,
  path: String,  // WebSocket path (currently unused in this implementation)
  handler: async (ServerConnection, socket.Addr) -> Unit,
  allow_failure?: Bool = true,
  max_connections?: Int,
) -> Unit
```

### Client Types

#### `Client`
Represents a WebSocket client connection.

**Methods:**
- `Client::connect(host: String, path: String, port?: Int, headers?: Map[String, String]) -> Client` - Connect to server
- `send_text(text: String)` - Send a text message
- `send_binary(data: Bytes)` - Send binary data
- `receive() -> Message` - Receive a message
- `ping(data?: Bytes)` - Send a ping frame
- `pong(data?: Bytes)` - Send a pong frame
- `close()` - Close the connection

### Message Types

#### `Message`
Represents a received WebSocket message.

```moonbit
struct Message {
  mtype: MessageType   // Text or Binary
  data: Bytes         // Message payload
}
```

#### `MessageType`
```moonbit
enum MessageType {
  Text    // UTF-8 text message
  Binary  // Binary data message
}
```

#### `Frame`
Low-level WebSocket frame representation.

```moonbit
struct Frame {
  fin: Bool       // Final frame flag
  opcode: OpCode  // Frame opcode
  payload: Bytes  // Frame payload
}
```

#### `OpCode`
WebSocket frame opcodes.

```moonbit
enum OpCode {
  Continuation  // 0x0 - Continuation frame
  Text          // 0x1 - Text frame
  Binary        // 0x2 - Binary frame
  Close         // 0x8 - Close frame
  Ping          // 0x9 - Ping frame
  Pong          // 0xA - Pong frame
}
```

### Error Types

#### `WebSocketError`
```moonbit
suberror WebSocketError {
  ProtocolError(String)   // Protocol violation
  InvalidOpCode           // Unknown opcode received
  InvalidCloseCode        // Invalid close status code
  ConnectionClosed        // Connection was closed
  InvalidFrame           // Malformed frame
  InvalidHandshake       // Handshake failed
}
```

#### `CloseCode`
Standard WebSocket close status codes.

```moonbit
enum CloseCode {
  Normal              // 1000 - Normal closure
  GoingAway           // 1001 - Endpoint going away
  ProtocolError       // 1002 - Protocol error
  UnsupportedData     // 1003 - Unsupported data
  InvalidFramePayload // 1007 - Invalid frame payload
  PolicyViolation     // 1008 - Policy violation
  MessageTooBig       // 1009 - Message too big
  InternalError       // 1011 - Internal server error
}
```

## Testing

The `examples/websocket_echo_server` directory contains:

1. **`main.mbt`** - A complete echo server example
2. **`test_client.html`** - A web-based test client

To test the WebSocket implementation:

1. Start the echo server (integrate with your async runtime)
2. Open `test_client.html` in a web browser
3. Click "Connect" to establish a WebSocket connection
4. Send messages and verify they are echoed back

## Protocol Compliance

This implementation follows RFC 6455 (The WebSocket Protocol) and includes:

- Proper HTTP upgrade handshake with Sec-WebSocket-Key/Accept
- Frame masking (required for client-to-server communication)
- Control frame handling (ping/pong/close)
- Message fragmentation and reassembly
- UTF-8 validation for text frames
- Close handshake with status codes

## Limitations

- SHA-1 implementation is simplified (should use cryptographic library in production)
- Random masking key generation is basic (should use secure random in production)
- No support for WebSocket extensions or subprotocols yet
- Path-based routing is simplified in the current server implementation

## Dependencies

This module depends on:
- `moonbitlang/async/io` - I/O abstractions
- `moonbitlang/async/socket` - TCP socket support
- `moonbitlang/async/http` - HTTP types (for upgrade handshake)
- `moonbitlang/async/internal/bytes_util` - Byte manipulation utilities

This module provides WebSocket client and server implementations for MoonBit's async library.

## Features

- ✅ WebSocket client connections
- ✅ WebSocket server connections  
- ✅ Text and binary message support
- ✅ Ping/Pong frames for connection keep-alive
- ✅ Automatic frame fragmentation handling
- ✅ Control frame handling (Close, Ping, Pong)
- ⚠️  Basic WebSocket handshake (simplified, needs SHA-1/Base64 for production)

## Quick Start

### Client Example

```moonbit
async fn main {
  // Connect to a WebSocket server
  let ws = @websocket.Client::connect("echo.websocket.org", "/")
  
  // Send a text message
  ws.send_text("Hello, WebSocket!")
  
  // Receive a message
  let msg = ws.receive()
  match msg.mtype {
    @websocket.MessageType::Text => {
      let text = @encoding/utf8.decode(msg.data)
      println("Received: \{text}")
    }
    @websocket.MessageType::Binary => {
      println("Received binary data: \{msg.data.length()} bytes")
    }
  }
  
  // Close the connection
  ws.close()
}
```

### Server Example

```moonbit
async fn main {
  // Run a WebSocket echo server on port 8080
  @websocket.run_server(
    @socket.Addr::parse("0.0.0.0:8080"),
    "/ws",  // WebSocket path
    fn(ws, addr) {
      println("New connection from \{addr}")
      
      // Echo loop
      for {
        let msg = ws.receive() catch {
          @websocket.ConnectionClosed => break
          err => {
            println("Error: \{err}")
            break
          }
        }
        
        // Echo back the message
        match msg.mtype {
          @websocket.MessageType::Text => {
            let text = @encoding/utf8.decode(msg.data)
            ws.send_text(text)
          }
          @websocket.MessageType::Binary => {
            ws.send_binary(msg.data)
          }
        }
      }
      
      ws.close()
    }
  )
}
```

## API Reference

### Types

#### `Client`
WebSocket client connection.

**Methods:**
- `connect(host: String, path: String, port?: Int, headers?: Map[String, String]) -> Client` - Connect to a WebSocket server
- `send_text(text: String) -> Unit` - Send a text message
- `send_binary(data: Bytes) -> Unit` - Send a binary message  
- `ping(data?: Bytes) -> Unit` - Send a ping frame
- `pong(data?: Bytes) -> Unit` - Send a pong frame
- `receive() -> Message` - Receive a message (blocks until complete message arrives)
- `close() -> Unit` - Close the connection

#### `ServerConnection`
WebSocket server connection.

**Methods:**
- `send_text(text: String) -> Unit` - Send a text message
- `send_binary(data: Bytes) -> Unit` - Send a binary message
- `ping(data?: Bytes) -> Unit` - Send a ping frame
- `pong(data?: Bytes) -> Unit` - Send a pong frame
- `send_close(code?: CloseCode, reason?: String) -> Unit` - Send a close frame
- `receive() -> Message` - Receive a message
- `close() -> Unit` - Close the connection

#### `Message`
A complete WebSocket message.

**Fields:**
- `mtype: MessageType` - Type of message (Text or Binary)
- `data: Bytes` - Message payload

#### `MessageType`
Message type enum:
- `Text` - UTF-8 text message
- `Binary` - Binary data message

#### `OpCode`
WebSocket frame opcodes:
- `Continuation` - Continuation frame
- `Text` - Text frame
- `Binary` - Binary frame
- `Close` - Connection close
- `Ping` - Ping frame
- `Pong` - Pong frame

#### `CloseCode`
Standard WebSocket close codes:
- `Normal` (1000) - Normal closure
- `GoingAway` (1001) - Endpoint going away
- `ProtocolError` (1002) - Protocol error
- `UnsupportedData` (1003) - Unsupported data type
- `InvalidFramePayload` (1007) - Invalid frame payload
- `PolicyViolation` (1008) - Policy violation
- `MessageTooBig` (1009) - Message too big
- `InternalError` (1011) - Internal server error

### Functions

#### `run_server`
Create and run a WebSocket server.

```moonbit
async fn run_server(
  addr: @socket.Addr,
  path: String,
  f: async (ServerConnection, @socket.Addr) -> Unit,
  allow_failure?: Bool,
  max_connections?: Int,
) -> Unit
```

**Parameters:**
- `addr` - The address to bind to
- `path` - WebSocket endpoint path (e.g., "/ws")
- `f` - Callback to handle each WebSocket connection
- `allow_failure?` - Whether to ignore handler failures (default: true)
- `max_connections?` - Maximum concurrent connections

## Protocol Details

This implementation follows the [RFC 6455](https://tools.ietf.org/html/rfc6455) WebSocket protocol specification.

### Frame Structure

WebSocket frames consist of:
1. FIN bit (1 bit) - Indicates final frame in message
2. Opcode (4 bits) - Frame type
3. Mask bit (1 bit) - Whether payload is masked
4. Payload length (7 bits, or extended to 16/64 bits)
5. Masking key (32 bits, if masked)
6. Payload data

### Client vs Server Behavior

- **Client frames** MUST be masked (per RFC 6455)
- **Server frames** MUST NOT be masked
- Both automatically handle ping/pong for connection keep-alive
- Close frames are echoed before closing the connection

## Limitations

1. **Handshake**: The current implementation uses a simplified WebSocket handshake. For production use, proper SHA-1 hashing and Base64 encoding of the Sec-WebSocket-Key should be implemented.

2. **TLS/WSS**: Secure WebSocket (wss://) connections are not yet implemented. Only plain ws:// connections are supported.

3. **Extensions**: WebSocket extensions (compression, etc.) are not supported.

4. **Subprotocols**: Subprotocol negotiation is not implemented.

## Future Enhancements

- [ ] Proper SHA-1 + Base64 for handshake
- [ ] TLS support for secure WebSocket (wss://)
- [ ] WebSocket extensions (permessage-deflate)
- [ ] Subprotocol negotiation
- [ ] Better integration with HTTP server for upgrade
- [ ] Configurable frame size limits
- [ ] Automatic reconnection support
