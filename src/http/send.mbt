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
  headers : Bytes
}

///|
fn[W : @io.Writer] Sender::new(
  w : W,
  headers? : Map[String, String] = {},
) -> Sender {
  let header_text = @buffer.new()
  for k, v in headers {
    header_text.write_string_utf8("\{k}: \{v}\r\n")
  }
  {
    writer: w,
    mode: SendingHeader,
    send_buf: FixedArray::make(1024, 0),
    send_len: 0,
    headers: header_text.contents(),
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
      if self.send_len + 7 >= self.send_buf.length() {
        self.flush()
      }
      let max_len = self.send_buf.length() - self.send_len - 7
      let len = @cmp.minimum(max_len, len)
      let len_str = encode_int(len, base=16)
      let len_str_len = len_str.length()
      self.send_buf.blit_from_bytes(self.send_len, len_str, 0, len_str_len)
      let curr_len = self.send_len + len_str_len
      self.send_buf[curr_len] = '\r'
      self.send_buf[curr_len + 1] = '\n'
      let curr_len = curr_len + 2
      self.send_buf.blit_from_bytes(curr_len, buf, offset, len)
      let curr_len = curr_len + len
      self.send_buf[curr_len] = '\r'
      self.send_buf[curr_len + 1] = '\n'
      self.send_len = curr_len + 2
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
      self.flush()
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
async fn Sender::end_body(self : Sender) -> Unit {
  if self.send_len + 5 > self.send_buf.length() {
    self.flush()
    self.writer.write("0\r\n\r\n")
  } else {
    self.send_buf.blit_from_bytes(self.send_len, "0\r\n\r\n", 0, 5)
    self.send_len += 5
    self.flush()
  }
  self.mode = SendingHeader
}

///|
async fn Sender::send_headers(
  self : Sender,
  headers : Map[String, String],
) -> Unit {
  for pair in headers.to_array() {
    let (k, v) = pair
    self
    ..write_string(k, encoding=UTF8)
    ..write(": ")
    ..write_string(v, encoding=UTF8)
    ..write("\r\n")
  }
}

///|
async fn Sender::send_request(
  self : Sender,
  meth : RequestMethod,
  path : String,
  extra_headers~ : Map[String, String],
) -> Unit {
  guard self.mode is SendingHeader
  match meth {
    Get => self.write("GET ")
    Head => self.write("HEAD ")
    Post => self.write("POST ")
    Put => self.write("PUT ")
    Delete => self.write("DELETE ")
    Connect => self.write("CONNECT ")
    Options => self.write("OPTIONS ")
    Trace => self.write("TRACE ")
    Patch => self.write("PATCH ")
  }
  self..write_string(path, encoding=UTF8)..write(" HTTP/1.1\r\n")
  self.write(self.headers)
  self.send_headers(extra_headers)
  self.write("Transfer-Encoding: chunked\r\n\r\n")
  self.mode = SendingBody
}

///|
async fn Sender::send_response(
  self : Sender,
  code : Int,
  reason : String,
  extra_headers~ : Map[String, String],
) -> Unit {
  guard self.mode is SendingHeader
  self
  ..write("HTTP/1.1 ")
  ..write(encode_int(code, base=10))
  ..write(" ")
  ..write_string(reason, encoding=UTF8)
  ..write("\r\n")
  self.write(self.headers)
  self.send_headers(extra_headers)
  self.write("Transfer-Encoding: chunked\r\n\r\n")
  self.mode = SendingBody
}
