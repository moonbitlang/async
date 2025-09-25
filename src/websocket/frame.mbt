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
priv struct Frame {
  mut fin : Bool
  mut rsv1 : Bool
  mut rsv2 : Bool
  mut rsv3 : Bool
  mut mask : Bool
  mut op_code : Byte
  mut masking_key : UInt
  mut data : Bytes
} derive(Default)

///|
/// TODO : use preallocated buffer
async fn Frame::write(self : Self, writer : &@io.Writer) -> Unit {
  // Write header
  let header = FixedArray::make(10, b'\x00') // maximum length
  // FIN + RSV bits + OpCode
  let mut b0 = self.op_code & 0x0F
  if self.fin {
    b0 = b0 | 0x80
  }
  if self.rsv1 {
    b0 = b0 | 0x40
  }
  if self.rsv2 {
    b0 = b0 | 0x20
  }
  if self.rsv3 {
    b0 = b0 | 0x10
  }
  header[0] = b0
  // Payload length + MASK bit
  let mask : Byte = if self.mask { 0x80 } else { 0x00 }
  if self.data.length() < 126 {
    header[1] = mask | self.data.length().to_byte()
    writer.write(header.unsafe_reinterpret_as_bytes()[:2])
  } else if self.data.length() < 65536 {
    header[1] = mask | 126
    header[2] = (self.data.length() >> 8).to_byte()
    header[3] = self.data.length().to_byte()
    writer.write(header.unsafe_reinterpret_as_bytes()[:4])
  } else {
    header[1] = mask | 127
    header[2] = (self.data.length() >> 56).to_byte()
    header[3] = (self.data.length() >> 48).to_byte()
    header[4] = (self.data.length() >> 40).to_byte()
    header[5] = (self.data.length() >> 32).to_byte()
    header[6] = (self.data.length() >> 24).to_byte()
    header[7] = (self.data.length() >> 16).to_byte()
    header[8] = (self.data.length() >> 8).to_byte()
    header[9] = self.data.length().to_byte()
    writer.write(header.unsafe_reinterpret_as_bytes()[:10])
  }

  // Mask and data
  if self.mask {
    let mask_data = self.masking_key.to_be_bytes()
    let buffer = FixedArray::make(self.data.length() + 4, b'\x00')
    buffer.blit_from_bytesview(0, mask_data)
    buffer.blit_from_bytesview(4, self.data)
    for i in 4..<buffer.length() {
      buffer[i] = buffer[i] ^ mask_data[i % 4]
    }
    writer.write(buffer.unsafe_reinterpret_as_bytes())
  } else {
    writer.write(self.data)
  }
}

///|
priv suberror UnexpectedEOF derive(Show)

///|
async fn Frame::read(read : &@io.Reader) -> Self {
  let self = Frame::default()
  // Read till length
  let header = read.read_exactly(2)
  let b0 = header[0]
  self.fin = (b0 & 0x80) != 0
  self.rsv1 = (b0 & 0x40) != 0
  self.rsv2 = (b0 & 0x20) != 0
  self.rsv3 = (b0 & 0x10) != 0
  self.op_code = b0 & 0x0F
  let b1 = header[1]
  self.mask = (b1 & 0x80) != 0
  let mut payload_len = (b1 & 0x7F).to_int()
  // Read extended length if needed
  if payload_len == 126 {
    let ext_len = read.read_exactly(2)
    payload_len = (ext_len[0].to_int() << 8) | ext_len[1].to_int()
  } else if payload_len == 127 {
    let ext_len = read.read_exactly(8)
    payload_len = ext_len[:].to_uint64_be().to_int()
  }
  // Read masking key and data
  if self.mask {
    let mask_key_bytes = read.read_exactly(4)
    self.masking_key = mask_key_bytes[:].to_uint_be()
    let buffer = FixedArray::make(payload_len, b'\x00')
    let mut offset = 0
    while offset < payload_len {
      let n = read.read(buffer, offset~)
      guard n > 0 else { raise UnexpectedEOF }
      offset += n
    }
    for i in 0..<buffer.length() {
      buffer[i] = buffer[i] ^ mask_key_bytes[i % 4]
    }
    self.data = buffer.unsafe_reinterpret_as_bytes()
  } else {
    self.data = read.read_exactly(payload_len)
  }
  self
}
