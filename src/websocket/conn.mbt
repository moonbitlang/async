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

///|
// we currently allow at most 2^16 bytes in a single frame when sending
const MAX_HEADER_SIZE : Int = 8 + 8 + 16

///|
const MASK_SIZE : Int = 4

///|
priv trait Transport: @io.Reader + @io.Writer {
  close(Self) -> Unit
}

///|
impl Transport for @http.Client with close(self) {
  self.close()
}

///|
impl Transport for @http.ServerConnection with close(self) {
  self.close()
}

///|
/// A WebSocket connection
struct Conn {
  mut closed : WebSocketError?
  transport : &Transport

  // state for reading
  read_buf : @io.ReaderBuffer
  mut read_opcode : OpCode?
  mut read_mask : Bytes?
  mut curr_frame_remaining : Int64
  mut curr_message : Message?

  // state for writing
  write_lock : @semaphore.Semaphore
  write_mask : @random.Rand?
  payload_start : Int
  mut write_opcode : OpCode?
  mut is_first_frame : Bool
  write_buf : FixedArray[Byte]
  mut write_len : Int
}

///|
priv enum MessageState {
  Active
  Closed
  Error(Error)
  Interrupted
}

///|
/// A message received from a WebSocket tunnel
pub struct Message {
  kind : MessageKind
  priv mut state : MessageState
  priv conn : Conn
}

///|
fn Conn::new(
  transport : &Transport,
  max_frame_size : Int,
  mask~ : @random.Rand?,
) -> Conn {
  {
    closed: None,
    transport,
    read_buf: @io.ReaderBuffer::new(),
    read_opcode: None,
    read_mask: None,
    curr_frame_remaining: 0,
    curr_message: None,
    write_lock: @semaphore.Semaphore::new(1),
    write_mask: mask,
    payload_start: if mask is Some(_) {
      MAX_HEADER_SIZE + MASK_SIZE
    } else {
      MAX_HEADER_SIZE
    },
    write_opcode: None,
    is_first_frame: true,
    write_buf: FixedArray::make(max_frame_size, 0),
    write_len: 0,
  }
}

///|
pub fn Conn::close(self : Conn) -> Unit {
  if self.curr_message is Some(message) {
    message.state = Error(ConnectionClosed(Normal, None))
    self.curr_message = None
  }
  if self.closed is None {
    self.closed = Some(ConnectionClosed(Normal, None))
  }
  self.transport.close()
}

///|
/// Initiating the connection closing process of WebSocket.
/// Note that `send_close` merely performs closing at WebSocket protocol level, so:
///
/// - `Conn::close` should be called anyway, even if `send_close` is called
/// - `Conn::send_close` should only be called when everything goes well.
///    For example it should NOT be called when protocol error or network error occurs.
pub async fn Conn::send_close(
  self : Conn,
  code? : CloseCode = Normal,
  reason? : String,
) -> Unit {
  if self.closed is Some(err) {
    raise err
  } else {
    self.closed = Some(ConnectionClosed(code, reason))
    self.send_close_unchecked(code, reason?)
  }
}

///|
async fn Conn::flush_frame_unprotected(
  self : Conn,
  op_code : OpCode,
  fin~ : Bool,
) -> Unit {
  // mask the frame if necessary
  let header_end = if self.write_mask is Some(rand) {
    let mask = rand.uint()
    self.write_buf.unsafe_write_uint32_be(self.payload_start - 4, mask)
    let mask_bytes = FixedArray::make(MASK_SIZE, b'\x00')
    mask_bytes.unsafe_write_uint32_be(0, mask)
    mask_payload(
      self.write_buf,
      mask_bytes.unsafe_reinterpret_as_bytes(),
      offset=self.payload_start,
      len=self.write_len,
    )
    self.payload_start - 4
  } else {
    self.payload_start
  }

  // fill header
  let frame_start = if self.write_len > 125 {
    self.write_buf.unsafe_write_uint16_be(
      header_end - 2,
      self.write_len.to_uint16(),
    )
    header_end - 4
  } else {
    header_end - 2
  }
  let frame_end = self.payload_start + self.write_len
  let fin : Byte = if fin { 0x80 } else { 0 }
  let masked : Byte = if self.write_mask is None { 0 } else { 0x80 }
  self.write_buf[frame_start] = fin | op_code.to_byte()
  self.write_buf[frame_start + 1] = masked |
    @cmp.minimum(self.write_len, 125).to_byte()

  // actually send the frame
  self.write_len = 0
  let data = self.write_buf.unsafe_reinterpret_as_bytes()[frame_start:frame_end]
  self.transport.write(data)
}

///|
async fn Conn::send_close_unchecked(
  self : Conn,
  code : CloseCode,
  reason? : String,
) -> Unit {
  self.write_lock.acquire()
  defer self.write_lock.release()

  // discard current message and send the `close` frame
  self.write_buf.unsafe_write_uint16_be(self.payload_start, code.to_uint16())
  let reason_bytes = @encoding/utf8.encode(reason.unwrap_or(""))
  if reason_bytes.length() > 123 {
    // Close reason too long
    // TODO: should we close the connection anyway?
    fail("Close reason too long")
  }
  self.write_buf.blit_from_bytes(
    self.payload_start + 2,
    reason_bytes,
    0,
    reason_bytes.length(),
  )
  self.write_len = 2 + reason_bytes.length()
  self.flush_frame_unprotected(Close, fin=true)
}

///|
async fn[X] Conn::protocol_error(self : Conn) -> X {
  if self.closed is None {
    self.closed = Some(ProtocolError)
    self.send_close_unchecked(ProtocolError)
  }
  raise WebSocketError::ProtocolError
}

///|
async fn Conn::recv_frame_header(self : Conn) -> FrameHeader {
  if self.closed is Some(err) {
    raise err
  }

  // Read first two bytes
  let header = self.transport.read_exactly(2)
  let byte0 = header[0]
  let byte1 = header[1]
  let fin = (byte0.to_int() & 0x80) != 0
  let rsv1 = (byte0.to_int() & 0x40) != 0
  let rsv2 = (byte0.to_int() & 0x20) != 0
  let rsv3 = (byte0.to_int() & 0x10) != 0
  let opcode_byte = byte0 & b'\x0F'
  let opcode = OpCode::from_byte(opcode_byte)
  let masked = (byte1.to_int() & 0x80) != 0
  let mut payload_len = (byte1.to_int() & 0x7F).to_int64()

  // No extensions supported, rejecting frames with RSV bits set
  if rsv1 || rsv2 || rsv3 {
    self.protocol_error()
  }

  // Validate payload length according to RFC 6455 Section 5.5
  if opcode is (Close | Ping | Pong) {
    if !fin || payload_len > 125L {
      self.protocol_error()
    }
  }

  // Validate payload length according to RFC 6455 Section 5.2
  if payload_len == 126L {
    let len_bytes = self.transport.read_exactly(2)
    guard len_bytes is [u16be(len)]
    payload_len = len.to_int64()
    if payload_len < 126L {
      self.protocol_error()
    }
  } else if payload_len == 127L {
    let len_bytes = self.transport.read_exactly(8)
    guard len_bytes is [u64be(len)]
    payload_len = len.reinterpret_as_int64()
    if payload_len < 65536L {
      self.protocol_error()
    }
    if payload_len < 0L {
      self.protocol_error()
    }
  }
  self.read_mask = if masked {
    Some(self.transport.read_exactly(4))
  } else {
    None
  }
  { opcode, fin, payload_len }
}

///|
/// reply `PING` frame with a `PONG` frame
async fn Conn::handle_ping(self : Conn, frame : FrameHeader) -> Unit {
  // the protocol requires `payload_len <= 125`
  let len = frame.payload_len.to_int()
  self.write_lock.acquire()
  defer self.write_lock.release()
  while self.write_len < len {
    let n = self.transport.read(
      self.write_buf,
      offset=self.payload_start + self.write_len,
      max_len=len - self.write_len,
    )
    guard n > 0 else { self.protocol_error() }
    self.write_len += n
  }
  if self.read_mask is Some(mask) {
    mask_payload(self.write_buf, mask, offset=self.payload_start, len~)
  }
  self.flush_frame_unprotected(Pong, fin=true)
}

///|
async fn Conn::handle_pong(self : Conn, frame : FrameHeader) -> Unit {
  // the protocol requires `payload_len <= 125`
  let len = frame.payload_len.to_int()
  guard self.transport.drop(len) == len else { self.protocol_error() }
}

///|
async fn Conn::handle_close(self : Conn, frame : FrameHeader) -> Unit {
  guard self.closed is None else {
    // we are the one who initiate the close, ignore the server's response
    ()
  }
  let len = frame.payload_len.to_int()
  let payload = FixedArray::make(len, b'\x00')
  for received = 0; received < len; {
    let n = self.transport.read(
      payload,
      offset=received,
      max_len=len - received,
    )
    guard n > 0 else { self.protocol_error() }
    continue received + n
  }
  if self.read_mask is Some(mask) {
    mask_payload(payload, mask, offset=0, len~)
  }
  let payload = payload.unsafe_reinterpret_as_bytes()
  let (close_code, reason) = if payload is [u16be(code), .. reason] {
    let reason = @encoding/utf8.decode(reason) catch {
      _ => self.protocol_error()
    }
    let reason = if reason.length() is 0 { None } else { Some(reason) }
    (CloseCode::from_uint(code), reason)
  } else {
    // the `close` packet we receive is empty
    (CloseCode::Normal, None)
  }
  self.closed = Some(ConnectionClosed(close_code, reason))
  self.send_close_unchecked(close_code, reason?)
}

///|
pub async fn Conn::recv(self : Conn) -> Message {
  guard self.read_opcode is None && self.curr_frame_remaining == 0 else {
    abort("calling `recv_message` in the middle of another message")
  }
  if self.curr_message is Some(msg) {
    while msg.drop(1024) == 1024 {
      ()
    }
    if msg.state is (Active | Closed) {
      msg.state = Interrupted
    }
  }
  let kind : MessageKind = loop self.recv_frame_header() {
    { opcode: Close, .. } as frame => {
      self.handle_close(frame)
      continue self.recv_frame_header()
    }
    { opcode: Ping, .. } as frame => {
      self.handle_ping(frame)
      continue self.recv_frame_header()
    }
    { opcode: Pong, .. } as frame => {
      self.handle_pong(frame)
      continue self.recv_frame_header()
    }
    { opcode: Continuation, .. } => self.protocol_error()
    { opcode: Text, fin, payload_len } => {
      if !fin {
        self.read_opcode = Some(Text)
      }
      self.curr_frame_remaining = payload_len
      Text
    }
    { opcode: Binary, fin, payload_len } => {
      if !fin {
        self.read_opcode = Some(Binary)
      }
      self.curr_frame_remaining = payload_len
      Binary
    }
  }
  let message = { kind, conn: self, state: Active }
  self.curr_message = Some(message)
  message
}

///|
pub impl @io.Reader for Message with _get_internal_buffer(self) {
  self.conn.read_buf
}

///|
pub impl @io.Reader for Message with _direct_read(self, buf, offset~, max_len~) {
  match self.state {
    Active => ()
    Closed => return 0
    Error(err) => raise err
    Interrupted =>
      abort(
        "A new message is requested before current message is completely read, there is probably a race condition bug in user code",
      )
  }
  let conn = self.conn
  if conn.closed is Some(err) {
    raise err
  }
  while conn.curr_frame_remaining == 0 {
    // if we are not in the last frame of a message,
    // the end of this frame is the end of the whole message
    if conn.read_opcode is None {
      self.state = Closed
      conn.curr_message = None
      return 0
    }

    // receive the continuation frames of a fragmented message
    let frame = conn.recv_frame_header()
    match frame.opcode {
      Continuation => {
        if frame.fin {
          // inidicate there is no more frame for this message
          conn.read_opcode = None
        }
        // continue with the next frame
        conn.curr_frame_remaining = frame.payload_len
      }
      Text | Binary =>
        // receiving a new message in the middle of
        // a fragmented message is not supported
        conn.protocol_error()
      Ping => conn.handle_ping(frame)
      Pong => conn.handle_pong(frame)
      Close => conn.handle_close(frame)
    }
  }

  // we have a non-empty frame pending, read from that frame
  let max_len = @cmp.minimum(conn.curr_frame_remaining, max_len.to_int64()).to_int()
  let n = conn.transport.read(buf, offset~, max_len~)
  conn.curr_frame_remaining -= n.to_int64()
  if conn.read_mask is Some(mask) {
    mask_payload(buf, mask, offset~, len=n)
  }
  n
}

///|
/// Start sending a new message to the server.
/// The content of the message can be sent by using the `self` as a `@io.Writer`
/// after calling `start_message`.
/// `end_message` must be explicitly called to terminate the message.
///
/// Writing message content is buffered.
/// To ensure immediate delivery of data, call `flush` manually.
///
/// `start_message` must NOT be called before the last message ends.
pub async fn Conn::start_message(self : Conn, kind : MessageKind) -> Unit {
  guard self.write_opcode is None else {
    abort("cannot start a new message before the last message end")
  }
  self.write_opcode = Some(
    match kind {
      Text => Text
      Binary => Binary
    },
  )
  self.is_first_frame = true
}

///|
/// End the message currently being sent,
/// flush all buffered data and tell the server the termination of current message.
///
/// `end_message` must be called after the `start_message`.
pub async fn Conn::end_message(self : Conn) -> Unit {
  guard self.write_opcode is Some(opcode) else {
    abort("`end_message` called outside a message")
  }
  self.write_lock.acquire()
  defer self.write_lock.release()
  self.write_opcode = None
  if self.is_first_frame {
    self.flush_frame_unprotected(opcode, fin=true)
  } else {
    self.flush_frame_unprotected(Continuation, fin=true)
  }
}

///|
/// Flush buffered content in current message,
/// ensure that all currently written content are immediately delivered to the peer.
pub async fn Conn::flush(self : Conn) -> Unit {
  guard self.write_len > 0 else {  }
  guard self.write_opcode is Some(opcode) else {
    abort("writing to WebSocket outside a message")
  }
  self.write_lock.acquire()
  defer self.write_lock.release()
  if self.is_first_frame {
    self.flush_frame_unprotected(opcode, fin=false)
    self.is_first_frame = false
  } else {
    self.flush_frame_unprotected(Continuation, fin=false)
  }
}

///|
/// Write content to the current message being sent.
/// The message may be fragmented into multiple WebSocket frames automatically.
/// Writing message content is buffered.
/// To ensure immediate delivery of data, call `flush` manually.
pub impl @io.Writer for Conn with write_once(self, buf, offset~, len~) {
  if self.payload_start + self.write_len >= self.write_buf.length() {
    self.flush()
  }
  let write_buf_offset = self.payload_start + self.write_len
  let len = @cmp.minimum(len, self.write_buf.length() - offset)
  self.write_buf.blit_from_bytes(write_buf_offset, buf, offset, len)
  self.write_len += len
  len
}

///|
/// Convenient helper for sending a single text message.
/// To send large message lazily, see `start_message`.
pub async fn Conn::send_text(self : Conn, text : StringView) -> Unit {
  self..start_message(Text)..write(text)..end_message()
}

///|
/// Convenient helper for sending a single binary message.
/// To send large message lazily, see `start_message`.
pub async fn Conn::send_binary(self : Conn, data : BytesView) -> Unit {
  self..start_message(Binary)..write(data)..end_message()
}
