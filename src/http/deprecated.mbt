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
    Get => logger.write_string("Get")
    Head => logger.write_string("Head")
    Post => logger.write_string("Post")
    Put => logger.write_string("Put")
    Delete => logger.write_string("Delete")
    Connect => logger.write_string("Connect")
    Options => logger.write_string("Options")
    Trace => logger.write_string("Trace")
    Patch => logger.write_string("Patch")
  }
}

///|
fn Protocol::write_show(self : Protocol, logger : &Logger) -> Unit {
  match self {
    Http => logger.write_string("Http")
    Https => logger.write_string("Https")
  }
}

///|
fn write_headers_show(headers : Map[String, String], logger : &Logger) -> Unit {
  logger.write_char('{')
  let mut first = true
  for key, value in headers {
    if first {
      first = false
    } else {
      logger.write_string(", ")
    }
    logger.write_string(key.escape())
    logger.write_string(": ")
    logger.write_string(value.escape())
  }
  logger.write_char('}')
}

///|
fn Request::write_show(self : Request, logger : &Logger) -> Unit {
  logger.write_string("{meth: ")
  self.meth.write_show(logger)
  logger.write_string(", path: ")
  logger.write_string(self.path.escape())
  logger.write_string(", headers: ")
  write_headers_show(self.headers, logger)
  logger.write_string("}")
}

///|
fn Response::write_show(self : Response, logger : &Logger) -> Unit {
  logger.write_string("{code: ")
  logger.write_object(self.code)
  logger.write_string(", reason: ")
  logger.write_string(self.reason.escape())
  logger.write_string(", headers: ")
  write_headers_show(self.headers, logger)
  logger.write_string("}")
}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for RequestMethod

///|
pub impl Show for RequestMethod with output(self, logger) {
  self.write_show(logger)
}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for Request

///|
pub impl Show for Request with output(self, logger) {
  self.write_show(logger)
}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for Response

///|
pub impl Show for Response with output(self, logger) {
  self.write_show(logger)
}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for Protocol

///|
pub impl Show for Protocol with output(self, logger) {
  self.write_show(logger)
}

///|
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for URIParseError

///|
pub impl Show for URIParseError with output(self, logger) {
  match self {
    InvalidFormat => logger.write_string("InvalidFormat")
    UnsupportedProtocol(protocol) =>
      logger
      ..write_string("UnsupportedProtocol(")
      ..write_object(protocol)
      .write_string(")")
  }
}

///|
#cfg(target="native")
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for ProxyError

///|
#cfg(target="native")
pub impl Show for ProxyError with output(self, logger) {
  match self {
    ProxyError(response) => {
      logger.write_string("ProxyError(")
      response.write_show(logger)
      logger.write_string(")")
    }
  }
}

///|
#cfg(target="native")
#deprecated("`Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.")
pub impl Show for HttpProtocolError

///|
#cfg(target="native")
pub impl Show for HttpProtocolError with output(self, logger) {
  match self {
    BadRequest => logger.write_string("BadRequest")
    HttpVersionNotSupported(version) =>
      logger
      ..write_string("HttpVersionNotSupported(")
      ..write_object(version)
      .write_string(")")
    NotImplemented => logger.write_string("NotImplemented")
  }
}
