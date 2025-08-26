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
  if path[:-1].rev_find_index('/') is Some(index) {
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
  conn
  ..write(b"HTTP/1.1 200 OK\r\n")
  ..write(b"Content-Type: text/html\r\n")
  ..write(b"Content-Length: ")
  ..write(content.length().to_string().to_ascii())
  ..write(b"\r\n\r\n")
  ..write(content.to_bytes())
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
  conn
  ..write(b"HTTP/1.1 200 OK\r\n")
  ..write(b"Transfer-Encoding: chunked\r\n")
  ..write("Content-Type: ")
  ..write(content_type)
  ..write(b"\r\n\r\n")
  let send_buf = FixedArray::make(1024, b'0')
  while file.read(send_buf) is n && n > 0 {
    conn
    ..write(n.to_string(radix=16).to_ascii())
    ..write("\r\n")
    ..write(send_buf.unsafe_reinterpret_as_bytes()[:n])
    ..write("\r\n")
  }
  conn.write("0\r\n\r\n")
}

///|
let page_for_404 : Bytes = b"<html><head></head><body>Page Not Found</body></html>"

///|
async fn serve_404(conn : @socket.TCP) -> Unit raise {
  conn
  ..write(b"HTTP/1.1 404 NotFound\r\n")
  ..write(b"Content-Type: text/html\r\n")
  ..write(b"Content-Length: ")
  ..write(page_for_404.length().to_string().to_ascii())
  ..write(b"\r\n\r\n")
  ..write(page_for_404)
}

///|
pub async fn server(
  ctx : @async.TaskGroup[Unit],
  path~ : Bytes,
  port~ : Int,
  log~ : (String) -> Unit = println,
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
      let src = @io.BufferedReader::new(conn)
      for {
        let (header, _) = parse_http_request(src)
        let path = header.path
        log("serving \{ascii_to_string(path)}")
        match header.cmd {
          Get => {
            let file = @fs.open(base_path + header.path, mode=ReadOnly) catch {
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
