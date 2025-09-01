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
test "send_request basic" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      @http.send_request(
        w,
        {
          meth: Get,
          path: "/",
          headers: [Header("Host", "x.y.org"), Header("User-Agent", "MoonBit")],
        },
        Empty,
      )
    })
    defer r.close()
    log.write_string(r.read_all() |> @bytes_util.ascii_to_string)
  })
  inspect(
    log.to_string(),
    content=(
      #|GET / HTTP/1.1\r
      #|Host: x.y.org\r
      #|User-Agent: MoonBit\r
      #|\r
      #|
    ),
  )
}

///|
test "send_request fixed body" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      @http.send_request(
        w,
        {
          meth: Get,
          path: "/",
          headers: [Header("Host", "x.y.org"), Header("User-Agent", "MoonBit")],
        },
        Fixed("message"),
      )
    })
    defer r.close()
    log.write_string(r.read_all() |> @bytes_util.ascii_to_string)
  })
  inspect(
    log.to_string(),
    content=(
      #|GET / HTTP/1.1\r
      #|Host: x.y.org\r
      #|User-Agent: MoonBit\r
      #|Content-Length: 7\r
      #|\r
      #|message
    ),
  )
}

///|
test "send_request stream" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      let file = @fs.open("src/http/moon.pkg.json", mode=ReadOnly)
      defer file.close()
      @http.send_request(
        w,
        {
          meth: Get,
          path: "/",
          headers: [Header("Host", "x.y.org"), Header("User-Agent", "MoonBit")],
        },
        Stream(file),
      )
    })
    defer r.close()
    log.write_string(r.read_all() |> @bytes_util.ascii_to_string)
  })
  inspect(
    log.to_string(),
    content=(
      #|GET / HTTP/1.1\r
      #|Host: x.y.org\r
      #|User-Agent: MoonBit\r
      #|Transfer-Encoding: chunked\r
      #|\r
      #|105\r
      #|{
      #|  "import": [
      #|    "moonbitlang/async/io",
      #|    "moonbitlang/async/socket",
      #|    "moonbitlang/async/tls",
      #|    "moonbitlang/async/internal/bytes_util"
      #|  ],
      #|  "test-import": [
      #|    "moonbitlang/async",
      #|    "moonbitlang/async/pipe",
      #|    "moonbitlang/async/fs"
      #|  ]
      #|}
      #|\r
      #|0\r
      #|\r
      #|
    ),
  )
}

///|
test "send_request stream2" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    let (r2, w2) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      defer r2.close()
      @http.send_request(
        w,
        {
          meth: Get,
          path: "/",
          headers: [Header("Host", "x.y.org"), Header("User-Agent", "MoonBit")],
        },
        Stream(r2),
      )
    })
    root.spawn_bg(fn() {
      defer w2.close()
      w2.write("abcd")
      @async.sleep(50)
      w2.write("efgh")
      @async.sleep(50)
      w2.write("ijkl")
    })
    defer r.close()
    log.write_string(r.read_all() |> @bytes_util.ascii_to_string)
  })
  inspect(
    log.to_string(),
    content=(
      #|GET / HTTP/1.1\r
      #|Host: x.y.org\r
      #|User-Agent: MoonBit\r
      #|Transfer-Encoding: chunked\r
      #|\r
      #|4\r
      #|abcd\r
      #|4\r
      #|efgh\r
      #|4\r
      #|ijkl\r
      #|0\r
      #|\r
      #|
    ),
  )
}

///|
test "send_response basic" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      @http.send_response(w, { code: 200, reason: "OK", headers: [] }, Empty)
    })
    defer r.close()
    log.write_string(r.read_all() |> @bytes_util.ascii_to_string)
  })
  inspect(
    log.to_string(),
    content=(
      #|HTTP/1.1 200 OK\r
      #|\r
      #|
    ),
  )
}
