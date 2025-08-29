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
async fn serve_directory(
  conn : @socket.TCP,
  dir : @fs.Directory,
  path~ : Bytes,
) -> Unit raise {
  let files = dir.read_all()
  files.sort()
  let content = @buffer.new()
  content
  ..write_bytes(b"<!DOCTYPE html><html><head></head><body>")
  ..write_bytes(b"<h1>")
  ..write_bytes(path)
  ..write_bytes(b"</h1>\n")
  ..write_bytes(b"<div style=\"margin: 1em; font-size: 15pt\">")
  if path[:-1].rev_find("/") is Some(index) {
    content
    ..write_bytes(b"<a href=\"")
    ..write_bytesview(if index == 0 { b"/" } else { path[:index] })
    ..write_bytes(b"\">..</a><br/><br/>\n")
  }
  for file in files {
    content..write_bytes(b"<a href=\"")..write_bytes(path)
    if path[path.length() - 1] != '/' {
      content.write_bytes(b"/")
    }
    content
    ..write_bytes(file)
    ..write_bytes(b"\">")
    ..write_bytes(file)
    ..write_bytes(b"</a><br/>\n")
  }
  content.write_bytes(b"</div></body></html>")
  @http.send_response(
    conn,
    { code: 200, reason: "OK", headers: [Header("Content-Type", "text/html")] },
    Fixed(content.to_bytes()),
  )
}

///|
async fn serve_file(
  conn : @socket.TCP,
  file : @fs.File,
  path~ : Bytes,
) -> Unit raise {
  let content_type : Bytes = match path {
    [.., .. ".png"] => "image/png"
    [.., .. ".jpg"] | "jpeg" => "image/jpeg"
    [.., .. ".html"] => "text/html"
    [.., .. ".css"] => "text/css"
    [.., .. ".js"] => "text/javascript"
    [.., .. ".mp4"] => "video/mp4"
    [.., .. ".mpv"] => "video/mpv"
    [.., .. ".mpeg"] => "video/mpeg"
    [.., .. ".mkv"] => "video/x-matroska"
    _ => "appliaction/octet-stream"
  }
  @http.send_response(
    conn,
    { code: 200, reason: "OK", headers: [Header("Content-Type", content_type)] },
    Stream(file),
  )
}

///|
let page_for_404 : Bytes = b"<html><head></head><body>Page Not Found</body></html>"

///|
async fn serve_404(conn : @socket.TCP) -> Unit raise {
  @http.send_response(
    conn,
    {
      code: 404,
      reason: "NotFound",
      headers: [Header("Content-Type", "text/html")],
    },
    Fixed(page_for_404),
  )
}

///|
pub async fn server(
  ctx : @async.TaskGroup[Unit],
  path~ : Bytes,
  port~ : Int,
  log? : (String) -> Unit = println,
) -> Unit raise {
  let base_path = path
  let server = @socket.TCPServer::new(@socket.Addr::parse("0.0.0.0:\{port}"))
  defer server.close()
  for {
    let (conn, addr) = server.accept()
    log("received new connection from \{addr}")
    ctx.spawn_bg(allow_failure=true, fn() {
      defer {
        log("closing connection from \{addr}")
        conn.close()
      }
      let src = @http.Reader::new(conn)
      for {
        let request = src.read_request()
        src.skip_body()
        let path = request.path
        log("serving \{ascii_to_string(path)}")
        match request.meth {
          Get => {
            let file = @fs.open(base_path + path, mode=ReadOnly) catch {
              _ => {
                serve_404(conn)
                continue
              }
            }
            defer file.close()
            if file.kind() is Directory {
              serve_directory(conn, file.as_dir(), path~)
            } else {
              serve_file(conn, file, path~)
            }
          }
          _ => ()
        }
      }
    })
  }
}

///|
fn main {
  let path = match @env.args() {
    [] | [_] => b"."
    [_, path, ..] => path.to_ascii()
  }
  @async.with_event_loop(ctx => server(ctx, path~, port=8000)) catch {
    err => println("server terminate due to \{err}")
  }
}
