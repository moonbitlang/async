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
test "basic seek" {
  let log = StringBuilder::new()
  let buf = FixedArray::make(6, b'0')
  @async.with_event_loop(fn(_) {
    let path = b"basic_seek_test\x00"
    // initialize
    let w = @fs.create(path, permission=0o644, sync=Full)
    log.write_string("initial size: \{w.size()}\n")
    w.write(b"abcdef")
    log.write_string("size after write: \{w.size()}\n")
    w.close()
    // first read
    let r = @fs.open(path, mode=ReadOnly)
    log.write_string("current size: \{r.size()}\n")
    r.read(buf)
    log.write_string("current content: \{buf}\n")
    r.close()
    // update content
    let w = @fs.open(path, mode=WriteOnly)
    ignore(w.seek(-2, mode=FromEnd))
    log.write_string("writing at position \{w.curr_pos()}\n")
    w.write(b"56")
    ignore(w.seek(2, mode=FromStart))
    log.write_string("writing at position \{w.curr_pos()}\n")
    w.write(b"34")
    ignore(w.seek(-4, mode=Relative))
    log.write_string("writing at position \{w.curr_pos()}\n")
    w.write(b"12")
    w.close()
    // read content
    let r = @fs.open(path, mode=ReadOnly)
    r.read(buf)
    log.write_string("final content: \{buf}\n")
    r.close()
    @fs.remove(path)
  })
  inspect(
    log.to_string(),
    content=(
      #|initial size: 0
      #|size after write: 6
      #|current size: 6
      #|current content: [b'\x61', b'\x62', b'\x63', b'\x64', b'\x65', b'\x66']
      #|writing at position 4
      #|writing at position 2
      #|writing at position 0
      #|final content: [b'\x31', b'\x32', b'\x33', b'\x34', b'\x35', b'\x36']
      #|
    ),
  )
}
