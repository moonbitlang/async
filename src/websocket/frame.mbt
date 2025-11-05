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
/// Read a WebSocket frame from a reader
async fn[R : @io.Reader] read_frame(reader : R) -> Frame {
  // Read first two bytes
  let header = reader.read_exactly(2)
  let byte0 = header[0]
  let byte1 = header[1]
  let fin = (byte0.to_int() & 0x80) != 0
  let opcode_byte = byte0 & b'\x0F'
  let opcode = match OpCode::from_byte(opcode_byte) {
    Some(op) => op
    None => raise FrameError("Invalid opcode: \{opcode_byte}")
  }
  let masked = (byte1.to_int() & 0x80) != 0
  let mut payload_len = (byte1.to_int() & 0x7F).to_int64()

  // Validate payload length according to RFC 6455
  if payload_len == 126L {
    let len_bytes = reader.read_exactly(2)
    guard len_bytes is [u16be(len), ..]
    payload_len = len.to_int64()
    if payload_len < 126L {
      raise FrameError(
        "Invalid payload length: 126-byte length used for length < 126",
      )
    }
  } else if payload_len == 127L {
    let len_bytes = reader.read_exactly(8)
    guard len_bytes is [u64be(len), ..]
    payload_len = len.reinterpret_as_int64()
    if payload_len < 65536L {
      raise FrameError(
        "Invalid payload length: 64-bit length used for length < 65536",
      )
    }
    if payload_len < 0L {
      raise FrameError(
        "Payload length too large (negative when interpreted as signed)",
      )
    }
  }

  // Check for reasonable payload size limit (1MB for now)
  if payload_len > 1048576L {
    raise FrameError("Payload too large: \{payload_len} bytes (max 1MB)")
  }

  // Read masking key if present
  let mask = if masked { Some(reader.read_exactly(4)) } else { None }

  // Read payload
  let payload_bytes = if payload_len > 0L {
    reader.read_exactly(payload_len.to_int())
  } else {
    Bytes::new(0)
  }

  // Unmask payload if needed
  if mask is Some(mask_bytes) {
    let payload_arr = payload_bytes.to_fixedarray()
    mask_payload(payload_arr, mask_bytes.to_fixedarray())
    { fin, opcode, payload: payload_arr.unsafe_reinterpret_as_bytes() }
  } else {
    { fin, opcode, payload: payload_bytes }
  }
}

///|
/// Write a WebSocket frame to a writer
async fn[W : @io.Writer] write_frame(
  writer : W,
  fin : Bool,
  opcode : OpCode,
  payload : Bytes,
  masked : Bool,
) -> Unit {
  let payload_len = payload.length().to_int64()

  // Validate payload size
  if payload_len > 1048576L {
    raise FrameError(
      "Payload too large for sending: \{payload_len} bytes (max 1MB)",
    )
  }
  let mut header_len = 2

  // Calculate extended length size
  if payload_len >= 126L && payload_len <= 65535L {
    header_len += 2
  } else if payload_len > 65535L {
    header_len += 8
  }

  // Add mask size if needed
  if masked {
    header_len += 4
  }

  // Build header
  let header = FixedArray::make(header_len, b'\x00')
  let mut offset = 0

  // First byte: FIN + opcode
  header[offset] = if fin {
    (0x80 | opcode.to_byte().to_int()).to_byte()
  } else {
    opcode.to_byte()
  }
  offset += 1

  // Second byte: MASK + payload length
  let mask_bit = if masked { 0x80 } else { 0 }
  if payload_len < 126L {
    header[offset] = (mask_bit | payload_len.to_int()).to_byte()
    offset += 1
  } else if payload_len <= 65535L {
    header[offset] = (mask_bit | 126).to_byte()
    offset += 1
    header.unsafe_write_uint16_be(offset, payload_len.to_uint16())
    offset += 2
  } else {
    header[offset] = (mask_bit | 127).to_byte()
    offset += 1
    header.unsafe_write_uint64_be(offset, payload_len.reinterpret_as_uint64())
    offset += 8
  }

  // Add masking key and mask payload if needed
  let final_payload = if masked {
    let mask = generate_mask()
    for i = 0; i < 4; i = i + 1 {
      header[offset + i] = mask[i]
    }
    let payload_arr = payload.to_fixedarray()
    mask_payload(payload_arr, mask)
    payload_arr.unsafe_reinterpret_as_bytes()
  } else {
    payload
  }

  // Write header and payload
  writer.write(header.unsafe_reinterpret_as_bytes())
  if payload_len > 0L {
    writer.write(final_payload)
  }
}
