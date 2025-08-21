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
#external
priv type C_Buffer

///|
#borrow(src)
extern "C" fn blit_to_c(
  src~ : FixedArray[Byte],
  dst~ : C_Buffer,
  offset~ : Int,
  len~ : Int,
) = "moonbitlang_async_blit_to_c"

///|
#borrow(dst)
extern "C" fn blit_from_c(
  src~ : C_Buffer,
  dst~ : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) = "moonbitlang_async_blit_from_c"

///|
priv enum EndpointState {
  Idle
  Blocked
  Error(Error)
  Closed
}

///|
priv struct Endpoint {
  data : FixedArray[Byte]
  mut state : EndpointState
  mut start : Int
  mut end : Int
  mut len : Int
  mut worker : @coroutine.Coroutine?
  waiters : Set[@coroutine.Coroutine]
}

///|
const BUFFER_SIZE = 1500

///|
#borrow(ep)
fn Endpoint::incref(ep : Endpoint) = "$moonbit.incref"

///|
fn Endpoint::read_size(ep : Endpoint) -> Int {
  @cmp.minimum(ep.len, ep.data.length() - ep.start)
}

///|
fn Endpoint::advance_read(ep : Endpoint, len : Int) -> Unit {
  ep.start = (ep.start + len) % ep.data.length()
  ep.len -= len
}

///|
fn Endpoint::write_size(ep : Endpoint) -> Int {
  ep.data.length() - @cmp.maximum(ep.end, ep.len)
}

///|
fn Endpoint::advance_write(ep : Endpoint, len : Int) -> Unit {
  ep.end = (ep.end + len) % ep.data.length()
  ep.len += len
}

///|
fn[R : @io.Reader] Endpoint::new_read(r : R) -> Endpoint noraise {
  let ep = {
    data: FixedArray::make(BUFFER_SIZE, 0),
    state: Idle,
    start: 0,
    end: 0,
    len: 0,
    worker: None,
    waiters: Set::new(),
  }
  let coro = @coroutine.spawn(fn() {
    try {
      @coroutine.pause()
      for {
        let remaining = ep.write_size()
        let remaining = if remaining == 0 {
          ep.state = Blocked
          @coroutine.suspend()
          ep.write_size()
        } else {
          remaining
        }
        guard remaining > 0
        let n = r.read(ep.data, offset=ep.end, max_len=remaining)
        ep.advance_write(n)
        for waiter in ep.waiters {
          waiter.wake()
        }
        if n == 0 {
          ep.state = Closed
          return
        }
      }
    } catch {
      err => {
        ep.state = Error(err)
        raise err
      }
    }
  })
  ep.worker = Some(coro)
  ep
}

///|
fn[W : @io.Writer] Endpoint::new_write(w : W) -> Endpoint noraise {
  let ep = {
    data: FixedArray::make(BUFFER_SIZE, 0),
    state: Idle,
    start: 0,
    end: 0,
    len: 0,
    worker: None,
    waiters: Set::new(),
  }
  let coro = @coroutine.spawn(fn() {
    try {
      @coroutine.pause()
      for {
        let pending = ep.read_size()
        let pending = if pending == 0 {
          ep.state = Blocked
          defer {
            ep.state = Idle
          }
          @coroutine.suspend()
          ep.read_size()
        } else {
          pending
        }
        guard pending > 0
        let n = w.write_once(
          ep.data.unsafe_reinterpret_as_bytes(),
          offset=ep.start,
          len=pending,
        )
        ep.advance_read(n)
        for waiter in ep.waiters {
          waiter.wake()
        }
      }
    } catch {
      err => {
        ep.state = Error(err)
        raise err
      }
    }
  })
  ep.worker = Some(coro)
  ep
}

///|
fn Endpoint::try_read(ep : Endpoint, dst : C_Buffer, len : Int) -> Int {
  guard ep.state is (Idle | Blocked) else { return -1 }
  let pending = ep.read_size()
  if pending == 0 {
    return -1
  }
  let actual_len = @cmp.minimum(len, pending)
  blit_to_c(src=ep.data, dst~, offset=ep.start, len=actual_len)
  ep.advance_read(actual_len)
  if ep.state is Blocked {
    ep.worker.unwrap().wake()
    ep.state = Idle
  }
  actual_len
}

///|
fn Endpoint::try_write(ep : Endpoint, src : C_Buffer, len : Int) -> Int {
  guard ep.state is (Idle | Blocked) else { return -1 }
  let remaining = ep.write_size()
  if remaining == 0 {
    return -1
  }
  let len = @cmp.minimum(remaining, len)
  blit_from_c(src~, dst=ep.data, offset=ep.end, len~)
  ep.advance_write(len)
  if ep.state is Blocked {
    ep.worker.unwrap().wake()
    ep.state = Idle
  }
  len
}

///|
async fn Endpoint::wait(ep : Endpoint) -> Unit raise {
  match ep.state {
    Error(err) => raise err
    Closed => raise ConnectionClosed
    Idle | Blocked => ()
  }
  let coro = @coroutine.current_coroutine()
  ep.waiters.add(coro)
  defer ep.waiters.remove(coro)
  @coroutine.suspend()
  match ep.state {
    Error(err) => raise err
    Closed | Idle | Blocked => ()
  }
}

///|
fn Endpoint::close(ep : Endpoint) -> Unit {
  if not(ep.state is Error(_)) {
    ep.state = Closed
  }
  ep.worker.unwrap().cancel()
  ep.worker = None
  for waiter in ep.waiters {
    waiter.wake()
  }
}

///|
#external
priv type BIO

///|
extern "C" fn BIO::get_endpoint(bio : BIO) -> Endpoint = "moonbitlang_async_tls_bio_get_endpoint"

///|
extern "C" fn BIO::set_flags(bio : BIO, flags : Int) = "moonbitlang_async_tls_bio_set_flags"

///|
extern "C" fn create_rbio(
  data : Endpoint,
  read : FuncRef[(BIO, C_Buffer, Int) -> Int],
) -> BIO = "moonbitlang_async_tls_create_rbio"

///|
extern "C" fn create_wbio(
  data : Endpoint,
  write : FuncRef[(BIO, C_Buffer, Int) -> Int],
) -> BIO = "moonbitlang_async_tls_create_wbio"

///|
const BIO_FLAGS_READ = 0x01

///|
const BIO_FLAGS_WRITE = 0x02

///|
const BIO_FLAGS_SHOULD_RETRY = 0x08

///|
fn BIO::read(bio : BIO, dst : C_Buffer, len : Int) -> Int {
  let ep = bio.get_endpoint()
  ep.incref()
  let ret = ep.try_read(dst, len)
  if ret < 0 && ep.state is (Idle | Blocked) {
    bio.set_flags(BIO_FLAGS_READ | BIO_FLAGS_SHOULD_RETRY)
  }
  ret
}

///|
fn BIO::write(bio : BIO, src : C_Buffer, len : Int) -> Int {
  let ep = bio.get_endpoint()
  ep.incref()
  let ret = ep.try_write(src, len)
  if ret < 0 && ep.state is (Idle | Blocked) {
    bio.set_flags(BIO_FLAGS_WRITE | BIO_FLAGS_SHOULD_RETRY)
  }
  ret
}
