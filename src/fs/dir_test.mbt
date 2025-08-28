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
test "as_dir" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(_) {
    let dir_file = @fs.open("src/fs", mode=ReadOnly)
    defer dir_file.close()
    guard dir_file.kind() is Directory
    let dir = dir_file.as_dir()
    if true { return }
    defer dir.close()
    let list = dir.read_all()
    list.sort()
    for file in list {
      let kind = @fs.open(b"src/fs/" + file, mode=ReadOnly).kind()
      log.write_string("\{@bytes_util.ascii_to_string(file)}: \{kind}\n")
    }
  })
  inspect(
    log.to_string(),
    content=(
      #|fs.mbt: Regular
      #|stub.c: Regular
      #|dir.mbt: Regular
      #|dir_test.mbt: Regular
      #|moon.pkg.json: Regular
      #|pkg.generated.mbti: Regular
      #|

    ),
  )
}
