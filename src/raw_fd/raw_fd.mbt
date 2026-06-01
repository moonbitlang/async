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
/// A wrapper around a raw file descriptor that can be used to
/// perform asynchronous IO on the raw file descriptor.
/// This is useful for binding special file descriptors
/// that are not natively supported by `moonbitlang/async`.
pub struct RawFd {
  fd : @fd_util.Fd
  priv io : @event_loop.IoHandle
}

///|
/// Create a new `RawFd` object from the underlying file descriptor.
/// The ownership of the file descriptor will be transferred to this function,
/// so the file descriptor must not be used or closed directly later,
/// even if creation of `RawFd` object failed.
#cfg(not(platform="windows"))
#alias(new, deprecated)
pub async fn RawFd::RawFd(fd : @fd_util.Fd) -> RawFd {
  let context = "@raw_fd.RawFd::new()"
  let kind = @event_loop.kind_of_fd(fd, context~)
  let is_async = @fd_util.fd_is_nonblocking(fd, context~)
  { fd, io: @event_loop.IoHandle::from_fd(fd, kind~, is_async~) }
}

///|
/// Create a new `RawFd` object from the underlying file descriptor.
/// The ownership of the file descriptor will be transferred to this function,
/// so the file descriptor must not be used or closed directly later,
/// even if creation of `RawFd` object failed.
///
/// The file descriptor (`HANDLE`) MUST NOT be overlapped.
#cfg(platform="windows")
#alias(new, deprecated)
pub async fn RawFd::RawFd(fd : @fd_util.Fd) -> RawFd {
  let context = "@raw_fd.RawFd::new()"
  let kind = @event_loop.kind_of_fd(fd, context~)
  { fd, io: @event_loop.IoHandle::from_fd(fd, kind~, is_async=false) }
}

///|
pub fn RawFd::close(self : RawFd) -> Unit {
  self.io.close()
}

///|
/// Perform a single `read`/`ReadFile` system call
/// asynchronously on a raw file descriptor object.
/// Data will be read into `buf[offset:offset+max_len]`.
/// The number of bytes actually read will be returned,
/// note that the number may be smaller than `max_len`.
/// A zero return value indicates EOF.
pub async fn RawFd::read(
  self : RawFd,
  buf : FixedArray[Byte],
  offset? : Int = 0,
  max_len? : Int = buf.length() - offset,
) -> Int {
  self.io.read(buf, offset~, len=max_len, context="@raw_fd.RawFd::read()")
}

///|
/// Perform a single `write`/`WriteFile` system call
/// asynchronously on a raw file descriptor object.
/// Data to write come from `buf[offset:offset+len]`.
/// The number of bytes actually written will be returned,
/// note that the number may be smaller than `len`.
pub async fn RawFd::write(
  self : RawFd,
  buf : Bytes,
  offset? : Int = 0,
  len? : Int = buf.length() - offset,
) -> Int {
  self.io.write(buf, offset~, len~, context="@raw_fd.RawFd::write()")
}

///|
/// A wrapper around a raw file descriptor that can be used to
/// perform asynchronous stream-based IO on the raw file descriptor
/// via the `@io.Reader`/`@io.Writer` interface.
/// This is useful for binding special file descriptors
/// that are not natively supported by `moonbitlang/async`.
pub struct RawFdStream {
  fd : @fd_util.Fd
  priv io : @event_loop.IoHandle
  priv read_buf : @io.ReaderBuffer
}

///|
/// Create a new `RawFdStream` object from the underlying file descriptor.
/// The ownership of the file descriptor will be transferred to this function,
/// so the file descriptor must not be used or closed directly later,
/// even if creation of `RawFdStream` object failed.
#cfg(not(platform="windows"))
pub async fn RawFdStream::RawFdStream(fd : @fd_util.Fd) -> RawFdStream {
  let context = "@raw_fd.RawFdStream()"
  let kind = @event_loop.kind_of_fd(fd, context~)
  let is_async = @fd_util.fd_is_nonblocking(fd, context~)
  let read_buf = @io.ReaderBuffer::new()
  { fd, io: @event_loop.IoHandle::from_fd(fd, kind~, is_async~), read_buf }
}

///|
/// Create a new `RawFdStream` object from the underlying file descriptor.
/// The ownership of the file descriptor will be transferred to this function,
/// so the file descriptor must not be used or closed directly later,
/// even if creation of `RawFdStream` object failed.
///
/// The file descriptor (`HANDLE`) MUST NOT be overlapped.
#cfg(platform="windows")
pub async fn RawFdStream::RawFdStream(fd : @fd_util.Fd) -> RawFdStream {
  let context = "@raw_fd.RawFdStream()"
  let kind = @event_loop.kind_of_fd(fd, context~)
  let read_buf = @io.ReaderBuffer::new()
  { fd, io: @event_loop.IoHandle::from_fd(fd, kind~, is_async=false), read_buf }
}

///|
pub fn RawFdStream::close(self : RawFdStream) -> Unit {
  self.io.close()
}

///|
pub impl @io.Reader for RawFdStream with fn _get_internal_buffer(self) {
  self.read_buf
}

///|
pub impl @io.Reader for RawFdStream with fn _direct_read(
  self,
  buf,
  offset~,
  max_len~,
) {
  self.io.read(buf, offset~, len=max_len, context="@raw_fd.RawFdStream::read()")
}

///|
pub impl @io.Writer for RawFdStream with fn write_once(self, buf, offset~, len~) {
  self.io.write(buf, offset~, len~, context="@raw_fd.RawFdStream::write()")
}
