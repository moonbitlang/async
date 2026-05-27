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
fn write_headers_show(headers : Map[String, String], logger : &Logger) -> Unit {
  logger <+ "{"
  let mut first = true
  for key, value in headers {
    if first {
      first = false
    } else {
      logger <+ ", "
    }
    logger <+ "\{key.escape()}: \{value.escape()}"
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
pub impl Show for Request

///|
pub impl Show for Request with fn output(self, logger) {
  self.write_show(logger)
}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for Response

///|
pub impl Show for Response with fn output(self, logger) {
  self.write_show(logger)
}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for Protocol

///|
pub impl Show for Protocol with fn output(self, logger) {
  self.write_show(logger)
}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for URIParseError

///|
pub impl Show for URIParseError with fn output(self, logger) {
  match self {
    InvalidFormat => logger <+ "InvalidFormat"
    UnsupportedProtocol(protocol) =>
      logger <+ "UnsupportedProtocol(\{to_repr(protocol)})"
  }
}

///|
#cfg(target="native")
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for ProxyError

///|
#cfg(target="native")
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
#cfg(target="native")
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for HttpProtocolError

///|
#cfg(target="native")
pub impl Show for HttpProtocolError with fn output(self, logger) {
  match self {
    BadRequest => logger <+ "BadRequest"
    HttpVersionNotSupported(version) =>
      logger <+ "HttpVersionNotSupported(\{to_repr(version)})"
    NotImplemented => logger <+ "NotImplemented"
  }
}
