# Socket Package

The `socket` package provides asynchronous network socket functionality for MoonBit applications. It supports both TCP and UDP protocols with IPv4 and IPv6 addressing.

## Overview

This package includes:

- **Address handling**: Parse and resolve network addresses
- **TCP connections**: Reliable, stream-oriented communication  
- **TCP servers**: Accept multiple client connections
- **UDP clients**: Connectionless packet communication
- **UDP servers**: Receive packets from multiple clients
- **Happy Eyeballs**: RFC 6555 compliant dual-stack connections

## Key Types

### `Addr`

Represents a network address (IP + port):

```moonbit
test "addr_basic" {
  // Create IPv4 address
  let addr = Addr::new(0x7F000001U, 8080) // 127.0.0.1:8080
  assert_eq(addr.port(), 8080)
  
  // Parse from string
  let ipv4 = try { Addr::parse("192.168.1.1:8080") } catch { _ => Addr::new(0U, 0) }
  let ipv6 = try { Addr::parse("[::1]:8080") } catch { _ => Addr::new(0U, 0) }
  
  assert_eq(ipv4.port(), 8080)
  assert_eq(ipv6.port(), 8080)
  assert_eq(ipv4.is_ipv6(), false)
  assert_eq(ipv6.is_ipv6(), true)
}
```

## IP Protocol Preferences

Control IPv4/IPv6 preference with `IpProtocolPreference`:

- `NoPreference`: Use first available (default)
- `OnlyV4`: IPv4 only
- `OnlyV6`: IPv6 only  
- `FavorV4`: Prefer IPv4, fallback to IPv6
- `FavorV6`: Prefer IPv6, fallback to IPv4

## Error Handling

The package defines two main error types:

- `InvalidAddr`: Raised when address parsing fails
- `ResolveHostnameError`: Raised when hostname resolution fails

```moonbit
test "error_handling" {
  let result = try { Addr::parse("invalid_format") } catch { _ => Addr::new(0U, 0) }
  // Invalid formats return a default address when caught
  assert_eq(result.port(), 0)
}
```

## Usage Patterns

This package provides asynchronous socket operations. Here are the main usage patterns:

### TCP Connections
```
// Connect to server (async)
// let conn = Tcp::connect(server_addr)!
// conn.write("Hello World")!
// conn.close()
```

### TCP Servers
```  
// Create and run server (async)
// let server = TcpServer::new(addr)!
// server.run_forever(fn(conn, addr) {
//   conn.write("Welcome!")!
// })!
```

### UDP Communication
```
// UDP client (async)
// let client = UdpClient::new(server_addr)!
// client.send(b"Hello Server")!
// client.close()

// UDP server (async) 
// let server = UdpServer::new(addr)!
// let (bytes, client_addr) = server.recvfrom(buffer)!
// server.sendto(b"Response", client_addr)!
```

### Dual Stack Support

IPv6 servers can accept both IPv4 and IPv6 connections when using the wildcard address `[::]` with `dual_stack=true`.

### Happy Eyeballs Algorithm

TCP hostname connections use RFC 6555 Happy Eyeballs for improved reliability by attempting both IPv4 and IPv6 connections simultaneously.
