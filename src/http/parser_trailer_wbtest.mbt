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
async test "trailer chunked" {
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("HTTP/1.1 200 OK\r\n")
      ..write("Transfer-Encoding: chunked\r\n")
      ..write("\r\n")
      ..write("4\r\nabcd\r\n")
      ..write("4\r\nxyzw\r\n")
      ..write("0\r\n")
      ..write("Trailer: value\r\n")
      .write("\r\n")
      // second message
      w
      ..write("HTTP/1.1 200 OK\r\n")
      ..write("Transfer-Encoding: chunked\r\n")
      ..write("\r\n")
      ..write("4\r\n1234\r\n")
      ..write("0\r\n")
      ..write("Trailer2: value2\r\n")
      .write("\r\n")
    }
    defer r.close()
    let input = Reader::new(r)
    // first message
    let response = input.read_response(
      request_method=None,
      auto_decompress=true,
    )
    inspect(response.code, content="200")
    debug_inspect(input.trailer, content="None")
    let chunk = @io.Reader::read_exactly(input, 4)
    inspect(@utf8.decode(chunk), content="abcd")
    debug_inspect(input.trailer, content="None")
    inspect(input.read_all().text(), content="xyzw")
    debug_inspect(
      input.trailer,
      content=(
        #|Some({ "Trailer": "value" })
      ),
    )
    // second message
    let response = input.read_response(
      request_method=None,
      auto_decompress=true,
    )
    inspect(response.code, content="200")
    debug_inspect(input.trailer, content="None")
    inspect(input.read_all().text(), content="1234")
    debug_inspect(
      input.trailer,
      content=(
        #|Some({ "Trailer2": "value2" })
      ),
    )
  }
}

///|
async test "trailer fixed length" {
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("HTTP/1.1 200 OK\r\n")
      ..write("Content-Length: 8\r\n")
      ..write("\r\n")
      ..write("abcd")
      .write("xyzw")
    }
    defer r.close()
    let input = Reader::new(r)
    let response = input.read_response(
      request_method=None,
      auto_decompress=true,
    )
    inspect(response.code, content="200")
    debug_inspect(input.trailer, content="None")
    let chunk = @io.Reader::read_exactly(input, 4)
    inspect(@utf8.decode(chunk), content="abcd")
    debug_inspect(input.trailer, content="None")
    inspect(input.read_all().text(), content="xyzw")
    debug_inspect(
      input.trailer,
      content=(
        #|Some({})
      ),
    )
  }
}

///|
async test "trailer close delimited" {
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("HTTP/1.1 200 OK\r\n")
      ..write("\r\n")
      ..write("abcd")
      .write("xyzw")
    }
    defer r.close()
    let input = Reader::new(r)
    let response = input.read_response(
      request_method=None,
      auto_decompress=true,
    )
    inspect(response.code, content="200")
    debug_inspect(input.trailer, content="None")
    let chunk = @io.Reader::read_exactly(input, 4)
    inspect(@utf8.decode(chunk), content="abcd")
    debug_inspect(input.trailer, content="None")
    inspect(input.read_all().text(), content="xyzw")
    debug_inspect(
      input.trailer,
      content=(
        #|Some({})
      ),
    )
  }
}
