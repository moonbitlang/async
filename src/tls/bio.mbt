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
priv enum EndpointState {
  Normal
  Closed
  Error(Error)
}

///|
priv struct Endpoint {
  mut state : EndpointState
  reader : &@io.Reader
  read_lock : @semaphore.Semaphore
  write_buf : @io_buffer.Buffer
  writer : &@io.Writer
  write_lock : @semaphore.Semaphore
}

///|
const BUFFER_SIZE = 4096

///|
fn @io.ReaderBuffer::repr(buf : Self) -> @io_buffer.Buffer = "%identity"

///|
fn Endpoint::new(reader : &@io.Reader, writer : &@io.Writer) -> Endpoint {
  reader._get_internal_buffer().repr().enlarge_to(BUFFER_SIZE)
  {
    state: Normal,
    reader,
    read_lock: @semaphore.Semaphore::new(1),
    write_buf: @io_buffer.new(BUFFER_SIZE),
    writer,
    write_lock: @semaphore.Semaphore::new(1),
  }
}

///|
async fn Endpoint::read_more(self : Endpoint) -> Unit {
  self.read_lock.acquire()
  defer self.read_lock.release()
  match self.state {
    Normal => ()
    Closed => raise ConnectionClosed
    Error(err) => raise err
  }
  let read_buf = self.reader._get_internal_buffer().repr()
  read_buf.enlarge_to(read_buf.len + 1)
  let end = read_buf.start + read_buf.len
  let max_len = @cmp.minimum(BUFFER_SIZE, read_buf.buf.length() - end)
  let n = self.reader._direct_read(read_buf.buf, offset=end, max_len~) catch {
    err => {
      self.state = Error(err)
      raise err
    }
  }
  if n is 0 {
    self.state = Closed
  } else {
    read_buf.len += n
  }
}

///|
async fn Endpoint::flush_write(self : Endpoint, flush_all~ : Bool) -> Unit {
  self.write_lock.acquire()
  defer self.write_lock.release()
  guard self.write_buf.len > 0 else {  }
  match self.state {
    Normal => ()
    Closed => raise ConnectionClosed
    Error(err) => raise err
  }
  if flush_all {
    let start = self.write_buf.start
    let end = self.write_buf.start + self.write_buf.len
    let data = self.write_buf.buf.unsafe_reinterpret_as_bytes()[start:end]
    self.writer.write(data)
    self.write_buf.start = 0
    self.write_buf.len = 0
  } else {
    let n = self.writer.write_once(
      self.write_buf.buf.unsafe_reinterpret_as_bytes(),
      offset=self.write_buf.start,
      len=self.write_buf.len,
    ) catch {
      err => {
        self.state = Error(err)
        raise err
      }
    }
    self.write_buf.drop(n)
  }
}

///|
#cfg(not(platform="windows"))
#external
priv type BIO

///|
#cfg(not(platform="windows"))
extern "C" fn BIO::get_endpoint(bio : BIO) -> Endpoint = "moonbitlang_async_tls_bio_get_endpoint"

///|
#cfg(not(platform="windows"))
extern "C" fn BIO::set_flags(bio : BIO, flags : Int) = "moonbitlang_async_tls_bio_set_flags"

///|
#cfg(not(platform="windows"))
#owned(data)
extern "C" fn create_bio(data : Endpoint) -> BIO = "moonbitlang_async_tls_create_bio"

///|
#cfg(not(platform="windows"))
const BIO_FLAGS_READ = 0x01

///|
#cfg(not(platform="windows"))
const BIO_FLAGS_WRITE = 0x02

///|
#cfg(not(platform="windows"))
const BIO_FLAGS_SHOULD_RETRY = 0x08

///|
#cfg(not(platform="windows"))
fn BIO::read(bio : BIO, dst : @c_buffer.Buffer, len : Int) -> Int {
  let ep = bio.get_endpoint()
  match ep.state {
    Normal => ()
    Closed => return 0
    Error(_) => return -1
  }
  let read_buf = ep.reader._get_internal_buffer().repr()
  guard read_buf.len > 0 else {
    bio.set_flags(BIO_FLAGS_READ | BIO_FLAGS_SHOULD_RETRY)
    -1
  }
  let len = @cmp.minimum(read_buf.len, len)
  dst.blit_from_bytes(
    src=read_buf.buf.unsafe_reinterpret_as_bytes(),
    offset=read_buf.start,
    len~,
  )
  read_buf.drop(len)
  len
}

///|
#cfg(not(platform="windows"))
fn BIO::write(bio : BIO, src : @c_buffer.Buffer, len : Int) -> Int {
  let ep = bio.get_endpoint()
  guard ep.state is Normal else { -1 }
  let end = ep.write_buf.start + ep.write_buf.len
  let remaining = ep.write_buf.buf.length() - end
  guard remaining > 0 else {
    bio.set_flags(BIO_FLAGS_WRITE | BIO_FLAGS_SHOULD_RETRY)
    -1
  }
  let len = @cmp.minimum(len, remaining)
  src.blit_to_bytes(dst=ep.write_buf.buf, offset=end, len~)
  ep.write_buf.len += len
  len
}
