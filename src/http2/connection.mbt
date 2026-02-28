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
/// HTTP/2 connection.
struct H2Connection {
  reader : &@io.Reader
  writer : &@io.Writer
  write_lock : @semaphore.Semaphore
  encoder : @hpack.Encoder
  decoder : @hpack.Decoder
  streams : Map[Int, H2Stream]
  mut next_stream_id : Int
  send_window : FlowWindow
  mut recv_window : Int
  local_settings : H2Settings
  remote_settings : H2Settings
  incoming_streams : @aqueue.Queue[H2Stream]
  mut goaway_sent : Bool
  mut last_stream_id : Int
  mut closed : Bool
  mut continuation_stream_id : Int
  continuation_buf : @buffer.Buffer
}

///|
/// Create a new H2Connection (base constructor).
fn H2Connection::new(
  reader : &@io.Reader,
  writer : &@io.Writer,
  is_client~ : Bool,
) -> H2Connection {
  {
    reader,
    writer,
    write_lock: @semaphore.Semaphore::new(1),
    encoder: @hpack.Encoder::new(),
    decoder: @hpack.Decoder::new(),
    streams: {},
    next_stream_id: if is_client {
      1
    } else {
      2
    },
    send_window: FlowWindow::new(default_initial_window_size),
    recv_window: default_initial_window_size,
    local_settings: H2Settings::default(),
    remote_settings: H2Settings::default(),
    incoming_streams: @aqueue.Queue::new(kind=Blocking(256)),
    goaway_sent: false,
    last_stream_id: 0,
    closed: false,
    continuation_stream_id: 0,
    continuation_buf: @buffer.new(),
  }
}

///|
/// Write a frame while holding the write lock.
async fn H2Connection::locked_write_frame(
  self : H2Connection,
  frame_type : FrameType,
  flags : Byte,
  stream_id : Int,
  payload : Bytes,
) -> Unit {
  self.write_lock.acquire()
  defer self.write_lock.release()
  write_frame(self.writer, frame_type, flags, stream_id, payload)
}

///|
/// Send a SETTINGS frame.
async fn H2Connection::send_settings(self : H2Connection) -> Unit {
  let payload = self.local_settings.encode()
  self.locked_write_frame(Settings, b'\x00', 0, payload)
}

///|
/// Send a SETTINGS ACK frame.
async fn H2Connection::send_settings_ack(self : H2Connection) -> Unit {
  self.locked_write_frame(Settings, flag_ack, 0, Bytes::make(0, b'\x00'))
}

///|
/// Send a PING frame.
async fn H2Connection::send_ping(
  self : H2Connection,
  data : Bytes,
  ack? : Bool = false,
) -> Unit {
  let flags = if ack { flag_ack } else { b'\x00' }
  self.locked_write_frame(Ping, flags, 0, data)
}

///|
/// Send a GOAWAY frame.
async fn H2Connection::send_goaway(
  self : H2Connection,
  error_code : H2ErrorCode,
  debug_data? : String = "",
) -> Unit {
  self.goaway_sent = true
  let buf = @buffer.new()
  let last_id = self.last_stream_id
  buf.write_int_be(last_id & 0x7fffffff)
  buf.write_int_be(error_code.to_int())
  for i = 0; i < debug_data.length(); i = i + 1 {
    buf.write_byte(debug_data[i].to_int().to_byte())
  }
  self.locked_write_frame(GoAway, b'\x00', 0, buf.to_bytes())
}

///|
/// Send a RST_STREAM frame.
async fn H2Connection::send_rst_stream(
  self : H2Connection,
  stream_id : Int,
  error_code : H2ErrorCode,
) -> Unit {
  let payload = encode_u32(error_code.to_int())
  self.locked_write_frame(RstStream, b'\x00', stream_id, payload)
}

///|
/// Send a WINDOW_UPDATE frame.
async fn H2Connection::send_window_update(
  self : H2Connection,
  stream_id : Int,
  increment : Int,
) -> Unit {
  let payload = encode_u32(increment & 0x7fffffff)
  self.locked_write_frame(WindowUpdate, b'\x00', stream_id, payload)
}

///|
/// Send HEADERS frame(s) for a stream.
/// HPACK encodes the headers, splits across HEADERS+CONTINUATION
/// if exceeding max_frame_size. Holds write_lock for entire sequence.
async fn H2Connection::send_headers(
  self : H2Connection,
  stream_id : Int,
  headers : Array[(String, String)],
  end_stream? : Bool = false,
) -> Unit {
  let encoded = self.encoder.encode(headers)
  let max_size = self.remote_settings.max_frame_size
  self.write_lock.acquire()
  defer self.write_lock.release()
  if encoded.length() <= max_size {
    let mut flags = flag_end_headers
    if end_stream {
      flags = flags.to_int().lor(flag_end_stream.to_int()).to_byte()
    }
    write_frame(self.writer, Headers, flags, stream_id, encoded)
  } else {
    let first_chunk = encoded[:max_size].to_bytes()
    let mut es_flags : Byte = b'\x00'
    if end_stream {
      es_flags = flag_end_stream
    }
    write_frame(self.writer, Headers, es_flags, stream_id, first_chunk)
    let mut offset = max_size
    while offset < encoded.length() {
      let remaining = encoded.length() - offset
      let chunk_size = @cmp.minimum(remaining, max_size)
      let is_last = offset + chunk_size >= encoded.length()
      let cont_flags = if is_last { flag_end_headers } else { b'\x00' }
      write_frame_from_slice(
        self.writer,
        Continuation,
        cont_flags,
        stream_id,
        encoded,
        offset,
        chunk_size,
      )
      offset = offset + chunk_size
    }
  }
}

///|
/// Process a received HEADERS/CONTINUATION payload through HPACK.
fn H2Connection::decode_headers(
  self : H2Connection,
  payload : Bytes,
) -> Array[(String, String)] raise {
  self.decoder.decode(payload)
}

///|
/// Allocate a new stream (client-side).
fn H2Connection::alloc_stream(self : H2Connection) -> H2Stream {
  let id = self.next_stream_id
  self.next_stream_id = self.next_stream_id + 2
  let stream = H2Stream::new(
    id,
    Open,
    self.remote_settings.initial_window_size,
    self.local_settings.initial_window_size,
    self,
  )
  self.streams[id] = stream
  if id > self.last_stream_id {
    self.last_stream_id = id
  }
  stream
}

///|
/// Get or create a stream for server-side incoming streams.
fn H2Connection::get_or_create_stream(
  self : H2Connection,
  stream_id : Int,
) -> H2Stream {
  match self.streams.get(stream_id) {
    Some(stream) => stream
    None => {
      let stream = H2Stream::new(
        stream_id,
        Open,
        self.remote_settings.initial_window_size,
        self.local_settings.initial_window_size,
        self,
      )
      self.streams[stream_id] = stream
      if stream_id > self.last_stream_id {
        self.last_stream_id = stream_id
      }
      stream
    }
  }
}

///|
/// Background frame reading loop.
/// Reads frames and dispatches them to the appropriate stream queues.
async fn H2Connection::read_loop(self : H2Connection) -> Unit {
  defer self.streams.clear()
  defer self.incoming_streams.close(clear=true)
  while not(self.closed) {
    let frame = read_frame(self.reader) catch {
      _ => {
        self.closed = true
        for _, stream in self.streams {
          if stream.error is None {
            stream.error = Some(NoError)
          }
          stream.inbound_data.close()
          stream.headers_ready.broadcast()
          stream.trailers_ready.broadcast()
        }
        self.incoming_streams.close(clear=true)
        break
      }
    }
    self.dispatch_frame(frame)
  }
}

///|
/// Dispatch a single received frame.
async fn H2Connection::dispatch_frame(
  self : H2Connection,
  frame : Frame,
) -> Unit {
  let ft = frame.header.frame_type
  let sid = frame.header.stream_id
  let flags = frame.header.flags
  let payload = frame.payload
  // Handle CONTINUATION accumulation
  if self.continuation_stream_id != 0 {
    if not(ft is Continuation) || sid != self.continuation_stream_id {
      self.send_goaway(ProtocolError, debug_data="expected CONTINUATION") catch {
        _ => ()
      }
      self.closed = true
      return
    }
    self.continuation_buf.write_bytes(payload)
    if has_flag(flags, flag_end_headers) {
      let full_payload = self.continuation_buf.to_bytes()
      self.continuation_buf.reset()
      let csid = self.continuation_stream_id
      self.continuation_stream_id = 0
      self.process_headers(csid, full_payload, has_flag(flags, flag_end_stream))
    }
    return
  }
  match ft {
    Data => self.handle_data(sid, flags, payload)
    Headers => self.handle_headers(sid, flags, payload)
    Priority => () // RFC 9113 deprecates priority. Accept and ignore.
    RstStream => self.handle_rst_stream(sid, payload)
    Settings => self.handle_settings(sid, flags, payload)
    PushPromise =>
      self.send_goaway(ProtocolError, debug_data="PUSH_PROMISE not supported") catch {
        _ => ()
      }
    Ping => self.handle_ping(sid, flags, payload)
    GoAway => ()
    // Could extract last_stream_id and error_code from payload
    WindowUpdate => self.handle_window_update(sid, payload)
    Continuation =>
      self.send_goaway(ProtocolError, debug_data="unexpected CONTINUATION") catch {
        _ => ()
      }
    Unknown(_) => () // Unknown frame types MUST be ignored
  }
}

///|
async fn H2Connection::handle_data(
  self : H2Connection,
  sid : Int,
  flags : Byte,
  payload : Bytes,
) -> Unit {
  if sid == 0 {
    self.send_goaway(ProtocolError, debug_data="DATA on stream 0") catch {
      _ => ()
    }
    return
  }
  match self.streams.get(sid) {
    Some(stream) => {
      stream.inbound_data.put(payload) catch {
        _ => ()
      }
      if has_flag(flags, flag_end_stream) {
        stream.state = match stream.state {
          Open => HalfClosedRemote
          HalfClosedLocal => Closed
          _ => stream.state
        }
        stream.inbound_data.put(Bytes::make(0, b'\x00')) catch {
          _ => ()
        }
      }
      self.recv_window = self.recv_window - payload.length()
      if self.recv_window < default_initial_window_size / 2 {
        let increment = default_initial_window_size - self.recv_window
        self.recv_window = self.recv_window + increment
        self.send_window_update(0, increment) catch {
          _ => ()
        }
      }
    }
    None => self.send_rst_stream(sid, StreamClosed) catch { _ => () }
  }
}

///|
async fn H2Connection::handle_headers(
  self : H2Connection,
  sid : Int,
  flags : Byte,
  payload : Bytes,
) -> Unit {
  if sid == 0 {
    self.send_goaway(ProtocolError, debug_data="HEADERS on stream 0") catch {
      _ => ()
    }
    return
  }
  let mut header_payload = payload
  let mut offset = 0
  if has_flag(flags, flag_padded) {
    let pad_length = payload[0].to_int()
    offset = 1
    header_payload = payload[offset:payload.length() - pad_length].to_bytes()
    offset = 0
  }
  if has_flag(flags, flag_priority) {
    offset = offset + 5
    header_payload = header_payload[offset:].to_bytes()
  } else if offset > 0 {
    header_payload = header_payload[offset:].to_bytes()
  }
  if has_flag(flags, flag_end_headers) {
    self.process_headers(sid, header_payload, has_flag(flags, flag_end_stream))
  } else {
    self.continuation_stream_id = sid
    self.continuation_buf.reset()
    self.continuation_buf.write_bytes(header_payload)
  }
}

///|
async fn H2Connection::handle_rst_stream(
  self : H2Connection,
  sid : Int,
  payload : Bytes,
) -> Unit {
  if payload.length() != 4 {
    self.send_goaway(FrameSizeError, debug_data="RST_STREAM bad size") catch {
      _ => ()
    }
    return
  }
  let error_code = H2ErrorCode::from_int(decode_u32(payload, 0))
  match self.streams.get(sid) {
    Some(stream) => {
      stream.error = Some(error_code)
      stream.state = Closed
      stream.inbound_data.close()
      stream.headers_ready.broadcast()
      stream.trailers_ready.broadcast()
    }
    None => ()
  }
}

///|
async fn H2Connection::handle_settings(
  self : H2Connection,
  sid : Int,
  flags : Byte,
  payload : Bytes,
) -> Unit {
  if sid != 0 {
    self.send_goaway(ProtocolError, debug_data="SETTINGS on non-zero stream") catch {
      _ => ()
    }
    return
  }
  if has_flag(flags, flag_ack) {
    return
  }
  self.remote_settings.apply(payload)
  self.send_settings_ack() catch {
    _ => ()
  }
}

///|
async fn H2Connection::handle_ping(
  self : H2Connection,
  sid : Int,
  flags : Byte,
  payload : Bytes,
) -> Unit {
  if sid != 0 {
    self.send_goaway(ProtocolError, debug_data="PING on non-zero stream") catch {
      _ => ()
    }
    return
  }
  if payload.length() != 8 {
    self.send_goaway(FrameSizeError, debug_data="PING bad size") catch {
      _ => ()
    }
    return
  }
  if not(has_flag(flags, flag_ack)) {
    self.send_ping(payload, ack=true) catch {
      _ => ()
    }
  }
}

///|
async fn H2Connection::handle_window_update(
  self : H2Connection,
  sid : Int,
  payload : Bytes,
) -> Unit {
  if payload.length() != 4 {
    self.send_goaway(FrameSizeError, debug_data="WINDOW_UPDATE bad size") catch {
      _ => ()
    }
    return
  }
  let increment = decode_u31(payload, 0)
  if increment == 0 {
    if sid == 0 {
      self.send_goaway(ProtocolError, debug_data="WINDOW_UPDATE increment 0") catch {
        _ => ()
      }
    } else {
      self.send_rst_stream(sid, ProtocolError) catch {
        _ => ()
      }
    }
    return
  }
  if sid == 0 {
    self.send_window.update(increment)
  } else {
    match self.streams.get(sid) {
      Some(stream) => stream.send_window.update(increment)
      None => ()
    }
  }
}

///|
/// Process decoded headers for a stream.
async fn H2Connection::process_headers(
  self : H2Connection,
  stream_id : Int,
  payload : Bytes,
  end_stream : Bool,
) -> Unit {
  let headers = self.decode_headers(payload) catch {
    _ => {
      self.send_rst_stream(stream_id, CompressionError) catch {
        _ => ()
      }
      return
    }
  }
  let header_map : Map[String, String] = {}
  for i = 0; i < headers.length(); i = i + 1 {
    let (name, value) = headers[i]
    header_map[name] = value
  }
  let stream = self.get_or_create_stream(stream_id)
  let is_new = stream.headers is None
  if is_new {
    // Initial headers
    stream.headers = Some(header_map)
    stream.headers_ready.broadcast()
  } else {
    // Trailing headers (HEADERS after DATA)
    stream.trailers = Some(header_map)
    stream.trailers_ready.broadcast()
  }
  if end_stream {
    stream.state = match stream.state {
      Open => HalfClosedRemote
      HalfClosedLocal => Closed
      _ => stream.state
    }
    if is_new {
      // Headers-only request (no DATA), signal end of data
      stream.inbound_data.put(Bytes::make(0, b'\x00')) catch {
        _ => ()
      }
    } else {
      // Trailers signal end of data too
      stream.inbound_data.put(Bytes::make(0, b'\x00')) catch {
        _ => ()
      }
    }
    // Wake trailers_ready in case someone is waiting and no trailers came
    stream.trailers_ready.broadcast()
  }
  if is_new && stream_id % 2 == 1 {
    self.incoming_streams.put(stream) catch {
      _ => ()
    }
  }
}
