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
test "basic create" {
  let buf = FixedArray::make(4, b'0')
  @async.with_event_loop(fn(_) {
    let path = b"basic_create_test\x00"
    let w = @fs.create(path, permission=0o644, sync=Full)
    w.write(b"abcd\n", 4)
    w.close()
    let r = @fs.open(path, mode=ReadOnly)
    r.read(buf, 4)
    r.close()
    @fs.remove(path)
  })
  inspect(buf, content="[b'\\x61', b'\\x62', b'\\x63', b'\\x64']")
}
