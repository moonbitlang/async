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
  conn : @http.ServerConnection,
  dir : @fs.Directory,
  path~ : Bytes,
) -> Unit {
  let files = dir.read_all()
  files.sort()
  let content = @buffer.new()
  content
  ..write_bytes(b"<!DOCTYPE html><html><head></head><body>")
  ..write_bytes(b"<h1>")
  ..write_bytes(path)
  ..write_bytes(b"</h1>\n")
  ..write_bytes(b"<div style=\"margin: 1em; font-size: 15pt\">")
  ..write_bytes(b"<a href=\"")
  ..write_bytes(path)
  ..write_bytes(b"?download_zip\">download as zip</a><br/><br/>\n")
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
  conn.send_response(
    200,
    "OK",
    extra_headers=[Header("Content-Type", "text/html")],
    Fixed(content.to_bytes()),
  )
}

///|
async fn serve_file(
  conn : @http.ServerConnection,
  file : @fs.File,
  path~ : Bytes,
) -> Unit {
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
  conn.send_response(
    200,
    "OK",
    extra_headers=[Header("Content-Type", content_type)],
    Stream(file),
  )
}

///|
async fn serve_zip(conn : @http.ServerConnection, path : Bytes) -> Unit {
  let base_name = if path.rev_find("/") is Some(i) {
    path[i + 1:].to_bytes()
  } else {
    path
  }
  @async.with_task_group(fn(group) {
    let (we_read_from_zip, zip_write_to_use) = @process.read_from_process()
    defer we_read_from_zip.close()
    group.spawn_bg(fn() {
      @process.run("zip", ["-q", "-r", "-", path], stdout=zip_write_to_use)
      |> ignore
    })
    conn.send_response(
      200,
      "OK",
      extra_headers=[
        Header("Content-Type", "application/octet-stream"),
        Header("Content-Disposition", "filename=" + base_name + ".zip"),
      ],
      Stream(we_read_from_zip),
    )
  })
}

///|
let page_for_404 : Bytes = b"<html><head></head><body>Page Not Found</body></html>"

///|
async fn serve_404(conn : @http.ServerConnection) -> Unit {
  conn.send_response(
    404,
    "NotFound",
    extra_headers=[Header("Content-Type", "text/html")],
    Fixed(page_for_404),
  )
}

///|
pub async fn server(
  path~ : Bytes,
  port~ : Int,
  log? : (String) -> Unit = println,
) -> Unit {
  let base_path = path
  let server = @socket.TCPServer::new(@socket.Addr::parse("0.0.0.0:\{port}"))
  defer server.close()
  @async.with_task_group(fn(ctx) {
    for {
      let (conn, addr) = server.accept()
      let conn = @http.ServerConnection::new(conn)
      log("received new connection from \{addr}")
      ctx.spawn_bg(allow_failure=true, fn() {
        defer {
          log("closing connection from \{addr}")
          conn.close()
        }
        for {
          let request = conn.read_request()
          let (path, download_zip) = match request.path {
            [.. path, .. "?download_zip"] => (path.to_bytes(), true)
            path => (path, false)
          }
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
                if download_zip {
                  serve_zip(conn, base_path + path)
                } else {
                  serve_directory(conn, file.as_dir(), path~)
                }
              } else {
                serve_file(conn, file, path~)
              }
            }
            _ => ()
          }
        }
      })
    }
  })
}

///|
async fn main {
  let path = match @env.args() {
    [] | [_] => b"."
    [_, path, ..] => path.to_ascii()
  }
  server(path~, port=8000) catch {
    err => println("server terminate due to \{err}")
  }
}
