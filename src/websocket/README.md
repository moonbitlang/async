# WebSocket API for MoonBit Async Library

This module provides a complete, battle-ready WebSocket implementation for the MoonBit async library, supporting both client and server functionality with full RFC 6455 compliance.

## Features

- **WebSocket Server**: Accept WebSocket connections with proper HTTP upgrade handshake
- **WebSocket Client**: Connect to WebSocket servers with full handshake validation
- **Message Types**: Support for text and binary messages with proper API design
- **Frame Management**: Automatic frame assembly/disassembly with validation
- **Control Frames**: Built-in ping/pong and close frame handling with proper codes and reasons
- **Masking**: Proper client-side masking for frame payloads using time-based entropy
- **Error Handling**: Comprehensive error types with descriptive messages
- **Protocol Compliance**: RFC 6455 compliance with proper validation
- **Robust Parsing**: Case-insensitive header parsing and edge case handling

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
    async fn(ws, client_addr) {
      println("New connection from \{client_addr}")
      
      try {
        for {
          let msg = ws.receive()
          match msg {
            websocket.Text(text) => {
              ws.send_text("Echo: " + text.to_string())
            }
            websocket.Binary(data) => {
              ws.send_binary(data.to_bytes())
            }
          }
        }
      } catch {
        websocket.ConnectionClosed(code) => 
          println("Connection closed with code: \{code}")
        err => println("Error: \{err}")
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
  match response {
    websocket.Text(text) => {
      println("Received: \{text}")
    }
    websocket.Binary(data) => {
      println("Received binary data")
    }
  }
  
  client.close()
}
```

## Key Improvements

This implementation has been thoroughly reviewed and improved for production readiness:

1. **Fixed Close Frame Handling**: Proper parsing of close codes and reasons from incoming close frames
2. **Client Connection State**: Fixed bug where client connections appeared closed immediately after handshake
3. **Random Mask Generation**: Uses system time for entropy instead of fixed pseudo-random values
4. **API Consistency**: Standardized Message API with separate MessageType enum
5. **Enhanced Error Handling**: InvalidHandshake and other errors now include descriptive reasons
6. **Frame Validation**: Comprehensive validation for malformed frames, invalid opcodes, and size limits
7. **Header Parsing**: Robust HTTP header parsing with case-insensitive matching and edge case handling
8. **Protocol Compliance**: Adherence to RFC 6455 specifications with proper validation

## Testing with JavaScript

The `examples/websocket_echo_server` directory contains a complete test setup:

1. **`main.mbt`** - A complete echo server example
2. **`test_client.html`** - A web-based test client

To test the WebSocket implementation:

1. Start the echo server using your MoonBit async runtime
2. Open `test_client.html` in a web browser
3. Click "Connect" to establish a WebSocket connection to ws://localhost:8080
4. Send messages and verify they are echoed back

## Protocol Compliance

This implementation follows RFC 6455 (The WebSocket Protocol) and includes:

- ✅ Proper HTTP upgrade handshake with Sec-WebSocket-Key/Accept validation
- ✅ Frame masking (required for client-to-server communication)
- ✅ Control frame handling (ping/pong/close) with proper codes and reasons
- ✅ Message fragmentation and reassembly
- ✅ Frame validation with size limits and malformed frame detection
- ✅ Case-insensitive HTTP header parsing
- ✅ Proper close handshake with status codes and reasons
- ✅ Time-based random masking key generation
- ✅ Comprehensive error handling with descriptive messages

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
- `send_close(code?: CloseCode, reason?: String)` - Send close frame with code and reason
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
enum Message {
  Binary(BytesView)  // Binary data message
  Text(StringView)   // UTF-8 text message
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

### Error Types

#### `WebSocketError`
```moonbit
suberror WebSocketError {
  ConnectionClosed(CloseCode)   // Connection was closed with specific code
  InvalidHandshake(String)      // Handshake failed with detailed reason
  FrameError(String)            // Malformed frame with details
}
```

## Production Considerations

- **Payload Size Limits**: Currently limited to 1MB per frame (configurable in frame.mbt)
- **Random Generation**: Uses time-based entropy; consider cryptographically secure random for high-security applications
- **TLS Support**: Plain WebSocket (ws://) only; secure WebSocket (wss://) requires TLS layer
- **Extensions**: WebSocket extensions (like compression) are not yet supported
- **Subprotocols**: Subprotocol negotiation is not implemented

## Dependencies

This module depends on:
- `moonbitlang/async/io` - I/O abstractions
- `moonbitlang/async/socket` - TCP socket support
- `moonbitlang/async/internal/time` - Time functions for random generation
- `moonbitlang/x/crypto` - SHA-1 hashing for handshake validation

## Performance

The implementation is designed for efficiency:
- Zero-copy frame assembly where possible
- Streaming frame reading without buffering entire messages
- Automatic ping/pong handling to maintain connections
- Efficient masking/unmasking operations
- Proper resource cleanup and connection management