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
priv enum SenderMode {
  SendingHeader
  SendingBody
}

///|
/// Provide send buffering & chunked encoding handling for sending HTTP request/response.
priv struct Sender {
  writer : &@io.Writer
  mut mode : SenderMode
  send_buf : FixedArray[Byte]
  mut send_len : Int
}

///|
fn[W : @io.Writer] Sender::new(w : W) -> Sender {
  {
    writer: w,
    mode: SendingHeader,
    send_buf: FixedArray::make(1024, 0),
    send_len: 0,
  }
}

///|
async fn Sender::flush(self : Sender) -> Unit {
  if self.send_len > 0 {
    self.writer.write(
      self.send_buf.unsafe_reinterpret_as_bytes()[:self.send_len],
    )
    self.send_len = 0
  }
}

///|
impl @io.Writer for Sender with write_once(self, buf, offset~, len~) {
  match self.mode {
    SendingHeader => {
      if self.send_len >= self.send_buf.length() {
        self.flush()
      }
      let len = @cmp.minimum(len, self.send_buf.length() - self.send_len)
      self.send_buf.blit_from_bytes(self.send_len, buf, offset, len)
      self.send_len += len
      len
    }
    SendingBody => {
      // Reserve enough space for chunk length and '\r\n' in the buffer,
      // so that we can commit the whole chunk in a single write to avoid small writes
      let max_len = self.send_buf.length() - 7
      let len = @cmp.minimum(max_len, len)
      self.send_buf[3] = '\r'
      self.send_buf[4] = '\n'
      self.send_buf.blit_from_bytes(5, buf, offset, len)
      self.send_buf[5 + len] = '\r'
      self.send_buf[6 + len] = '\n'
      let len_str = encode_int(len, base=16)
      let start = 3 - len_str.length()
      self.send_buf.blit_from_bytes(start, len_str, 0, len_str.length())
      self.writer.write(
        self.send_buf.unsafe_reinterpret_as_bytes()[start:len + 7],
      )
      len
    }
  }
}

///|
impl @io.Writer for Sender with write_reader(self, reader) {
  match self.mode {
    SendingHeader =>
      for {
        if self.send_len >= self.send_buf.length() {
          self.flush()
        }
        let n = reader.read(self.send_buf, offset=self.send_len)
        if n == 0 {
          break
        }
      }
    SendingBody => {
      self.send_buf[3] = '\r'
      self.send_buf[4] = '\n'
      let max_len = self.send_buf.length() - 7
      for {
        let len = reader.read(self.send_buf, offset=5, max_len~)
        if len == 0 {
          break
        }
        self.send_buf[5 + len] = '\r'
        self.send_buf[6 + len] = '\n'
        let len_str = encode_int(len, base=16)
        let start = 3 - len_str.length()
        self.send_buf.blit_from_bytes(start, len_str, 0, len_str.length())
        self.writer.write(
          self.send_buf.unsafe_reinterpret_as_bytes()[start:len + 7],
        )
      }
    }
  }
}

///|
async fn Sender::start_body(self : Sender) -> Unit {
  self.write("\r\n")
  self.flush()
  self.mode = SendingBody
}

///|
async fn Sender::end_body(self : Sender) -> Unit {
  self.writer.write("0\r\n\r\n")
  self.mode = SendingHeader
}

///|
async fn Sender::send_headers(self : Sender, headers : Array[Header]) -> Unit {
  for header in headers {
    let Header(k, v) = header
    self
    ..write_string(k, encoding=UTF8)
    ..write(": ")
    ..write_string(v, encoding=UTF8)
    ..write("\r\n")
  }
}
