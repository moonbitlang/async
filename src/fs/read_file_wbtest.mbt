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
struct ChunkedReader {
  data : FixedArray[Byte]
  chunks : Array[Int]
  buffer : @io.ReaderBuffer
  mut offset : Int
  mut chunk_index : Int
}

///|
fn ChunkedReader::new(size : Int, chunks : Array[Int]) -> ChunkedReader {
  {
    data: FixedArray::make(size, b'x'),
    chunks,
    buffer: @io.ReaderBuffer::new(),
    offset: 0,
    chunk_index: 0,
  }
}

///|
impl @io.Reader for ChunkedReader with fn _get_internal_buffer(self) {
  self.buffer
}

///|
impl @io.Reader for ChunkedReader with fn _direct_read(
  self,
  dst,
  offset~,
  max_len~,
) {
  guard self.offset < self.data.length() else { return 0 }
  let requested = if self.chunk_index < self.chunks.length() {
    let requested = self.chunks[self.chunk_index]
    self.chunk_index += 1
    requested
  } else {
    max_len
  }
  let n = @cmp.minimum(
    max_len,
    @cmp.minimum(requested, self.data.length() - self.offset),
  )
  dst.unsafe_blit(offset, self.data, self.offset, n)
  self.offset += n
  n
}

///|
async test "read_file size hint handles short reads" {
  let reader = ChunkedReader::new(10, [1, 2, 3, 4])
  assert_eq(read_all_with_size_hint(reader, 10).binary(), Bytes::make(10, b'x'))
}

///|
async test "read_file size hint handles an early EOF" {
  let reader = ChunkedReader::new(5, [2, 2, 1])
  assert_eq(read_all_with_size_hint(reader, 10).binary(), Bytes::make(5, b'x'))
}

///|
async test "read_file size hint retains data beyond the hint" {
  let reader = ChunkedReader::new(10, [2, 2, 3, 3])
  assert_eq(read_all_with_size_hint(reader, 4).binary(), Bytes::make(10, b'x'))
}

///|
async test "read_file size hint of zero still reads to EOF" {
  let reader = ChunkedReader::new(10, [3, 3, 4])
  assert_eq(read_all_with_size_hint(reader, 0).binary(), Bytes::make(10, b'x'))
}

///|
async test "read_file regular file size boundaries" {
  for size in [0, 1, 1023, 1024, 1025, 64 * 1024 + 1] {
    let path = "_build/read_file_regular_\{size}"
    let expected = Bytes::make(size, b'x')
    write_file(path, expected, create_mode=CreateOrTruncate, sync=NoSync)
    let actual = read_file(path).binary()
    remove(path)
    assert_eq(actual, expected)
  }
}

///|
#cfg(all(target="native", platform="linux"))
async test "read_file reads a zero-sized procfs regular file" {
  let path = "/proc/self/cmdline"
  let file = open(path, mode=ReadOnly)
  assert_eq(file.kind(), Regular)
  assert_eq(file.size(), 0L)
  file.close()
  assert_true(read_file(path).binary().length() > 0)
}

///|
#cfg(all(target="native", not(platform="windows")))
#borrow(path)
extern "C" fn make_read_file_fifo(
  path : @os_string.OsString,
  mode : Int,
) -> Int = "mkfifo"

///|
#cfg(all(target="native", not(platform="windows")))
async test "read_file falls back for a fifo" {
  @async.with_task_group() <| group => {
    let path = "_build/read_file_fifo"
    if make_read_file_fifo(@os_string.encode(path), 0o600) < 0 {
      @os_error.check_errno("read_file fifo test")
    }
    group.add_defer(() => remove(path))
    let read_task = group.spawn(() => read_file(path).binary())
    let writer = open(path, mode=WriteOnly)
    writer.write(b"abcd")
    writer.close()
    assert_eq(read_task.wait(), b"abcd")
  }
}

///|
#cfg(all(target="native", platform="windows"))
async test "read_file falls back for a Windows named pipe" {
  @async.with_task_group() <| group => {
    let context = "read_file named pipe test"
    let path = "\\\\.\\pipe\\moonbitlang_async_read_file_test"
    let server = @fd_util.create_named_pipe_server(
      @os_string.encode(path),
      is_async=true,
    )
    if !@fd_util.fd_is_valid(server) {
      @os_error.check_errno(context)
    }
    let read_task = group.spawn(() => read_file(path).binary())
    @async.sleep(200)
    let writer = @event_loop.IoHandle::from_fd(server, kind=@fd_util.Pipe)
    ignore(writer.write(b"abcd", offset=0, len=4, context~))
    writer.close()
    assert_eq(read_task.wait(), b"abcd")
  }
}
