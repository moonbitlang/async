///|
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

///|
/// The test program of `src/tty/tty_test.mbt`, run under `script`,
/// which makes a fresh pseudo terminal its controlling terminal.
///
/// `ttyd <port>` connects to `127.0.0.1:<port>` and serves JSON-RPC 2.0
/// requests on that connection, one JSON value per line, one request at a time,
/// until the connection is closed. Each method performs one `@tty` operation:
///
/// - `enter_raw_mode`, `leave_raw_mode`: result `null`
/// - `size`: result `[rows, cols]`
/// - `read_event`, params `{"timeout"?: ms}`: result `{"type":"input","bytes":"<base64>"}`,
///   `{"type":"resize"}`, `{"type":"eof"}`, or `{"type":"timeout"}`
/// - `read_exactly`, params `{"len": n}`: `@io.Reader::read_exactly`,
///   result the bytes in base64
/// - `write`, params `{"bytes": "<base64>"}`: result `null`
///
/// An error raised by `@tty` is reported as error `-32000` with its description.
async fn main {
  guard @env.args() is [_, port] else { fail("usage: ttyd <port>") }
  let tty = @tty.open()
  let rpc = @socket.Tcp::connect(@socket.Addr::parse("127.0.0.1:\{port}"))
  defer rpc.close()
  while rpc.read_until("\n") is Some(line) {
    rpc.write("\{respond(tty, @json.parse(line)).stringify()}\n")
  }
}

///|
suberror RpcError {
  RpcError(code~ : Int32, message~ : String)
}

///|
async fn respond(tty : @tty.Tty, request : Json) -> Json {
  guard request
    is {
      "jsonrpc": "2.0",
      "method": String(name),
      "id"? : id,
      "params"? : params,
      ..
    } else {
    return {
      "jsonrpc": "2.0",
      "id": null,
      "error": { "code": -32600, "message": "Invalid Request" },
    }
  }
  let id = id.unwrap_or(null)
  let params = params.unwrap_or(Json::empty_object())
  try call(tty, name, params) catch {
    RpcError(code~, message~) =>
      {
        "jsonrpc": "2.0",
        "id": id,
        "error": { "code": Json(code), "message": Json(message) },
      }
    err =>
      {
        "jsonrpc": "2.0",
        "id": id,
        "error": { "code": -32000, "message": Json(@debug.to_string(err)) },
      }
  } noraise {
    result => { "jsonrpc": "2.0", "id": id, "result": result }
  }
}

///|
async fn call(tty : @tty.Tty, name : String, params : Json) -> Json {
  match name {
    "enter_raw_mode" => {
      tty.enter_raw_mode()
      null
    }
    "leave_raw_mode" => {
      tty.leave_raw_mode()
      null
    }
    "size" => {
      let (rows, cols) = tty.size()
      [rows, cols]
    }
    "read_event" => {
      let event = match params {
        { "timeout": Number(timeout, ..), .. } =>
          match
            @async.with_timeout_opt(timeout.to_int(), () => tty.read_event()) {
            None => return { "type": "timeout" }
            Some(event) => event
          }
        { "timeout": _, .. } =>
          raise invalid_params("`timeout` must be a number")
        _ => tty.read_event()
      }
      match event {
        Some(Input(bytes)) =>
          { "type": "input", "bytes": @base64.encode(bytes) }
        Some(Resize) => { "type": "resize" }
        None => { "type": "eof" }
      }
    }
    "read_exactly" => {
      guard params is { "len": Number(len, ..), .. } else {
        raise invalid_params("`len` must be a number")
      }
      Json(@base64.encode(tty.read_exactly(len.to_int())))
    }
    "write" => {
      guard params is { "bytes": String(bytes), .. } else {
        raise invalid_params("`bytes` must be a base64 string")
      }
      tty.write(@base64.decode(bytes))
      null
    }
    _ => raise RpcError(code=-32601, message="Method not found: \{name}")
  }
}

///|
fn invalid_params(message : String) -> RpcError {
  RpcError(code=-32602, message~)
}
