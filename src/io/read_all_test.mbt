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
async test "read_all basic" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(() => writer(log, w))
    inspect(r.read_all().text(), content="abcdefghijkl")
  })
}

///|
async test "read_all large data" {
  @async.with_task_group(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      w.write(Bytes::make(4097, 0))
    })
    inspect(r.read_all().binary().length(), content="4097")
  })
}
