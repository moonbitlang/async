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
fn log_headers(headers : Map[String, String], logger : &Logger) -> Unit {
  for k, v in headers {
    logger.write_string("\{k}: \{v}\n")
  }
}

///|
fn log_request(req : Request, logger : &Logger) -> Unit {
  logger.write_string("\{req.meth} \{req.path}\n")
  log_headers(req.headers, logger)
}

///|
fn log_response(req : Response, logger : &Logger) -> Unit {
  logger.write_string("\{req.code} \{req.reason}\n")
  log_headers(req.headers, logger)
}

///|
async test "read_request basic" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = @io.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      w
      ..write("GET / HTTP/1.1\r\n")
      ..write("Host: x.y.org\r\n")
      ..write("User-Agent: MoonBit\r\n\r\n")
    })
    defer r.close()
    let input = Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    log.write_string(input.read_all().text())
  })
  inspect(
    log.to_string(),
    content=(
      #|Get /
      #|host: x.y.org
      #|user-agent: MoonBit
      #|
    ),
  )
}

///|
async test "read_request fixed body" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = @io.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      w
      ..write("GET / HTTP/1.1\r\n")
      ..write("Host: x.y.org\r\n")
      ..write("User-Agent: MoonBit\r\n")
      ..write("Content-Length: 7\r\n\r\n")
      ..write("message")
    })
    defer r.close()
    let input = Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    log.write_string(input.read_all().text())
  })
  inspect(
    log.to_string(),
    content=(
      #|Get /
      #|host: x.y.org
      #|user-agent: MoonBit
      #|content-length: 7
      #|message
    ),
  )
}

///|
async test "read_request chunked" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = @io.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      w
      ..write("GET / HTTP/1.1\r\n")
      ..write("Host: x.y.org\r\n")
      ..write("User-Agent: MoonBit\r\n")
      ..write("Transfer-Encoding: chunked\r\n\r\n")
      ..write("4\r\n")
      ..write("abcd\r\n")
      ..write("10\r\n")
      ..write("abcdefghijklmnop\r\n")
      ..write("0\r\n\r\n")
    })
    defer r.close()
    let input = Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    log.write_string(input.read_all().text())
  })
  inspect(
    log.to_string(),
    content=(
      #|Get /
      #|host: x.y.org
      #|user-agent: MoonBit
      #|transfer-encoding: chunked
      #|abcdabcdefghijklmnop
    ),
  )
}

///|
async test "read_request stream" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = @io.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      w
      ..write("GET / HTTP/1.1\r\n")
      ..write("Host: x.y.org\r\n")
      ..write("User-Agent: MoonBit\r\n")
      ..write("Transfer-Encoding: chunked\r\n\r\n")
      @async.sleep(50)
      log.write_string("writing data...\n")
      w.write("4\r\nabcd\r\n")
      @async.sleep(50)
      log.write_string("writing data...\n")
      w.write("4\r\nefgh\r\n")
      @async.sleep(50)
      log.write_string("writing data...\n")
      w.write("4\r\nijkl\r\n")
      w.write("0\r\n\r\n")
    })
    defer r.close()
    let input = Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    while input.read_some() is Some(data) {
      let data = @encoding/utf8.decode(data)
      log.write_string("received \{data} from body\n")
    }
  })
  inspect(
    log.to_string(),
    content=(
      #|Get /
      #|host: x.y.org
      #|user-agent: MoonBit
      #|transfer-encoding: chunked
      #|writing data...
      #|received abcd from body
      #|writing data...
      #|received efgh from body
      #|writing data...
      #|received ijkl from body
      #|
    ),
  )
}

///|
async test "multiple request" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = @io.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      w
      ..write("GET / HTTP/1.1\r\n")
      ..write("Host: x.y.org\r\n")
      ..write("User-Agent: MoonBit\r\n")
      ..write("Transfer-Encoding: chunked\r\n\r\n")
      @async.sleep(50)
      log.write_string("writing data...\n")
      w.write("4\r\nabcd\r\n")
      @async.sleep(50)
      log.write_string("writing data...\n")
      w.write("4\r\nefgh\r\n")
      @async.sleep(50)
      log.write_string("writing data...\n")
      w.write("4\r\nijkl\r\n")
      w.write("0\r\n\r\n")
      @async.sleep(50)
      w
      ..write("GET / HTTP/1.1\r\n")
      ..write("Host: z.w.org\r\n")
      ..write("User-Agent: MoonBit\r\n")
      ..write("Content-Length: 8\r\n\r\n")
      ..write("message2")
    })
    defer r.close()
    let input = Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    log
    ..write_string(input.read_all().text())
    ..write_string("\n\n=========\n\n")
    let request = input.read_request()
    log_request(request, log)
    log.write_string(input.read_all().text())
  })
  inspect(
    log.to_string(),
    content=(
      #|Get /
      #|host: x.y.org
      #|user-agent: MoonBit
      #|transfer-encoding: chunked
      #|writing data...
      #|writing data...
      #|writing data...
      #|abcdefghijkl
      #|
      #|=========
      #|
      #|Get /
      #|host: z.w.org
      #|user-agent: MoonBit
      #|content-length: 8
      #|message2
    ),
  )
}

///|
async test "read_response basic" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = @io.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      w
      ..write("HTTP/1.1 200 OK\r\n")
      ..write("Content-Length: 7\r\n\r\n")
      ..write("message")
    })
    defer r.close()
    let input = Reader::new(r)
    let response = input.read_response()
    log_response(response, log)
    log.write_string(input.read_all().text())
  })
  inspect(
    log.to_string(),
    content=(
      #|200 OK
      #|content-length: 7
      #|message
    ),
  )
}
