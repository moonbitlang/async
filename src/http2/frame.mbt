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
/// Read a single HTTP/2 frame from a reader.
/// Returns the frame header and payload.
async fn read_frame(reader : &@io.Reader) -> Frame {
  let header_bytes = reader.read_exactly(9)
  let length = (header_bytes[0].to_int() << 16) |
    (header_bytes[1].to_int() << 8) |
    header_bytes[2].to_int()
  let frame_type = FrameType::from_byte(header_bytes[3])
  let flags = header_bytes[4]
  let stream_id = ((header_bytes[5].to_int() & 0x7f) << 24) |
    (header_bytes[6].to_int() << 16) |
    (header_bytes[7].to_int() << 8) |
    header_bytes[8].to_int()
  let payload = if length > 0 {
    reader.read_exactly(length)
  } else {
    Bytes::make(0, b'\x00')
  }
  { header: { length, frame_type, flags, stream_id }, payload }
}

///|
/// Write a frame to a writer.
async fn write_frame(
  writer : &@io.Writer,
  frame_type : FrameType,
  flags : Byte,
  stream_id : Int,
  payload : Bytes,
) -> Unit {
  let length = payload.length()
  let header = FixedArray::make(9, b'\x00')
  header[0] = ((length >> 16) & 0xff).to_byte()
  header[1] = ((length >> 8) & 0xff).to_byte()
  header[2] = length.land(0xff).to_byte()
  header[3] = frame_type.to_byte()
  header[4] = flags
  header[5] = ((stream_id >> 24) & 0x7f).to_byte()
  header[6] = ((stream_id >> 16) & 0xff).to_byte()
  header[7] = ((stream_id >> 8) & 0xff).to_byte()
  header[8] = stream_id.land(0xff).to_byte()
  writer.write(header.unsafe_reinterpret_as_bytes())
  if length > 0 {
    writer.write(payload)
  }
}

///|
/// Write a frame header followed by data from a slice of bytes.
/// Avoids copying for DATA frames.
async fn write_frame_from_slice(
  writer : &@io.Writer,
  frame_type : FrameType,
  flags : Byte,
  stream_id : Int,
  data : Bytes,
  offset : Int,
  length : Int,
) -> Unit {
  let header = FixedArray::make(9, b'\x00')
  header[0] = ((length >> 16) & 0xff).to_byte()
  header[1] = ((length >> 8) & 0xff).to_byte()
  header[2] = length.land(0xff).to_byte()
  header[3] = frame_type.to_byte()
  header[4] = flags
  header[5] = ((stream_id >> 24) & 0x7f).to_byte()
  header[6] = ((stream_id >> 16) & 0xff).to_byte()
  header[7] = ((stream_id >> 8) & 0xff).to_byte()
  header[8] = stream_id.land(0xff).to_byte()
  writer.write(header.unsafe_reinterpret_as_bytes())
  if length > 0 {
    writer.write(data[offset:offset + length])
  }
}

///|
/// Encode a 32-bit unsigned integer into 4 bytes (big-endian).
fn encode_u32(value : Int) -> Bytes {
  let buf = FixedArray::make(4, b'\x00')
  buf[0] = ((value >> 24) & 0xff).to_byte()
  buf[1] = ((value >> 16) & 0xff).to_byte()
  buf[2] = ((value >> 8) & 0xff).to_byte()
  buf[3] = value.land(0xff).to_byte()
  buf.unsafe_reinterpret_as_bytes()
}

///|
/// Decode a 32-bit unsigned integer from 4 bytes (big-endian).
fn decode_u32(data : Bytes, offset : Int) -> Int {
  (data[offset].to_int() << 24) |
  (data[offset + 1].to_int() << 16) |
  (data[offset + 2].to_int() << 8) |
  data[offset + 3].to_int()
}

///|
/// Decode a 31-bit unsigned integer from 4 bytes (big-endian), masking top bit.
fn decode_u31(data : Bytes, offset : Int) -> Int {
  ((data[offset].to_int() & 0x7f) << 24) |
  (data[offset + 1].to_int() << 16) |
  (data[offset + 2].to_int() << 8) |
  data[offset + 3].to_int()
}
