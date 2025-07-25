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
test "read EOF" {
  let buf = FixedArray::make(16, b'0')
  @async.with_event_loop(fn(_) {
    let path = b"read_eof_test\x00"
    {
      let w = @fs.create(path, permission=0o644, sync=Full)
      defer w.close()
      w.write(b"abcd")
    }
    let n = {
      let r = @fs.open(path, mode=ReadOnly)
      defer r.close()
      r.read(buf)
    }
    @fs.remove(path)
    assert_eq(n, 4)
    inspect(
      buf.unsafe_reinterpret_as_bytes()[0:n],
      content=(
        #|b"\x61\x62\x63\x64"
      ),
    )
  })
}
