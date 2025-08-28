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
test "readdir clear errno" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(_) {
    // do something to set a non-zero errno
    try @fs.open("/this/file/does/not/exist", mode=ReadOnly) catch {
      _ => ()
    } noraise {
      _ => ()
    }
    let dir = @fs.opendir("src/fs")
    defer dir.close()
    let list = dir.read_all().map(name => @bytes_util.ascii_to_string(name))
    log.write_object(list.length())
  })
  inspect(log.to_string(), content="10")
}
