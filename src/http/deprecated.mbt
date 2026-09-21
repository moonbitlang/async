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
fn RequestMethod::write_show(self : RequestMethod, logger : &Logger) -> Unit {
  match self {
    Get => logger <+ "Get"
    Head => logger <+ "Head"
    Post => logger <+ "Post"
    Put => logger <+ "Put"
    Delete => logger <+ "Delete"
    Connect => logger <+ "Connect"
    Options => logger <+ "Options"
    Trace => logger <+ "Trace"
    Patch => logger <+ "Patch"
  }
}

///|
fn Protocol::write_show(self : Protocol, logger : &Logger) -> Unit {
  match self {
    Http => logger <+ "Http"
    Https => logger <+ "Https"
  }
}

///|
fn write_headers_show(headers : Headers, logger : &Logger) -> Unit {
  logger <+ "{"
  let mut first = true
  for key, value in headers {
    if first {
      first = false
    } else {
      logger <+ ", "
    }
    logger <+ "\{key.0.escape()}: \{value.escape()}"
  }
  logger <+ "}"
}

///|
fn Request::write_show(self : Request, logger : &Logger) -> Unit {
  logger <+ "{meth: "
  self.meth.write_show(logger)
  logger <+ ", path: \{self.path.escape()}, headers: "
  write_headers_show(self.headers, logger)
  logger <+ "}"
}

///|
fn Response::write_show(self : Response, logger : &Logger) -> Unit {
  logger <+ "{code: \{self.code}, reason: \{self.reason.escape()}, headers: "
  write_headers_show(self.headers, logger)
  logger <+ "}"
}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for RequestMethod

///|
pub impl Show for RequestMethod with fn output(self, logger) {
  self.write_show(logger)
}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
#doc(hidden)
pub extend RequestMethod with Show::{to_string}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for Request

///|
pub impl Show for Request with fn output(self, logger) {
  self.write_show(logger)
}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
#doc(hidden)
pub extend Request with Show::{to_string}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for Response

///|
pub impl Show for Response with fn output(self, logger) {
  self.write_show(logger)
}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
#doc(hidden)
pub extend Response with Show::{to_string}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for Protocol

///|
pub impl Show for Protocol with fn output(self, logger) {
  self.write_show(logger)
}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
#doc(hidden)
pub extend Protocol with Show::{to_string}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for URIParseError

///|
pub impl Show for URIParseError with fn output(self, logger) {
  match self {
    InvalidFormat => logger <+ "InvalidFormat"
    UnsupportedProtocol(protocol) =>
      logger <+ "UnsupportedProtocol(\{Repr(protocol)})"
  }
}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
#doc(hidden)
pub extend URIParseError with Show::{to_string}

///|
#cfg(any(target="native", target="wasm"))
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for ProxyError

///|
#cfg(any(target="native", target="wasm"))
pub impl Show for ProxyError with fn output(self, logger) {
  match self {
    ProxyError(response) => {
      logger <+ "ProxyError("
      response.write_show(logger)
      logger <+ ")"
    }
  }
}

///|
#cfg(any(target="native", target="wasm"))
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
#doc(hidden)
pub extend ProxyError with Show::{to_string}

///|
#cfg(any(target="native", target="wasm"))
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for HttpProtocolError

///|
#cfg(any(target="native", target="wasm"))
pub impl Show for HttpProtocolError with fn output(self, logger) {
  match self {
    BadRequest => logger <+ "BadRequest"
    HttpVersionNotSupported(version) =>
      logger <+ "HttpVersionNotSupported(\{Repr(version)})"
    NotImplemented => logger <+ "NotImplemented"
  }
}

///|
#cfg(any(target="native", target="wasm"))
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
#doc(hidden)
pub extend HttpProtocolError with Show::{to_string}

///|
#cfg(any(target="native", target="wasm"))
#deprecated
#doc(hidden)
pub extend ProxyError with Debug::{to_repr}

///|
#cfg(any(target="native", target="wasm"))
#deprecated
#doc(hidden)
pub extend ProxyError with ToJson::{to_json}

///|
#cfg(any(target="native", target="wasm"))
#deprecated
#doc(hidden)
pub extend ProxyError with Show::{output}

///|
#cfg(any(target="native", target="wasm"))
#deprecated
#doc(hidden)
pub extend HttpProtocolError with Debug::{to_repr}

///|
#cfg(any(target="native", target="wasm"))
#deprecated
#doc(hidden)
pub extend HttpProtocolError with ToJson::{to_json}

///|
#cfg(any(target="native", target="wasm"))
#deprecated
#doc(hidden)
pub extend HttpProtocolError with Show::{output}

///|
#deprecated
#doc(hidden)
pub extend RequestMethod with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend RequestMethod with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend RequestMethod with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
#deprecated
#doc(hidden)
pub extend RequestMethod with Hash::{hash, hash_combine}

///|
#deprecated
#doc(hidden)
pub extend RequestMethod with ToJson::{to_json}

///|
#deprecated
#doc(hidden)
pub extend RequestMethod with Show::{output}

///|
#deprecated
#doc(hidden)
pub extend Request with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend Request with ToJson::{to_json}

///|
#deprecated
#doc(hidden)
pub extend Request with Show::{output}

///|
#deprecated
#doc(hidden)
pub extend Response with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend Response with ToJson::{to_json}

///|
#deprecated
#doc(hidden)
pub extend Response with Show::{output}

///|
#deprecated
#doc(hidden)
pub extend Protocol with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend Protocol with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend Protocol with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
#deprecated
#doc(hidden)
pub extend Protocol with Hash::{hash, hash_combine}

///|
#deprecated
#doc(hidden)
pub extend Protocol with ToJson::{to_json}

///|
#deprecated
#doc(hidden)
pub extend Protocol with Show::{output}

///|
#deprecated
#doc(hidden)
pub extend URIParseError with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend URIParseError with ToJson::{to_json}

///|
#deprecated
#doc(hidden)
pub extend URIParseError with Show::{output}

///|
#cfg(any(target="native", target="wasm"))
#deprecated
#doc(hidden)
pub extend IncorrectBodyLength with Debug::{to_repr}

///|
#cfg(any(target="native", target="wasm"))
#deprecated
#doc(hidden)
pub extend IncorrectBodyLength with ToJson::{to_json}

///|
#deprecated
#doc(hidden)
pub extend Cookie with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend Cookie with ToJson::{to_json}

///|
#deprecated
#doc(hidden)
pub extend Client with @io.Reader::{_direct_read, _get_internal_buffer}

///|
#cfg(any(target="native", target="wasm"))
#deprecated
#doc(hidden)
pub extend ServerConnection with @io.Reader::{
  _direct_read,
  _get_internal_buffer,
}
