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
test "read_all" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(_) {
    let dir = @fs.opendir("src/fs")
    defer dir.close()
    let list = dir.read_all().map(name => @bytes_util.ascii_to_string(name))
    list.sort()
    log.write_object(list)
  })
  inspect(
    log.to_string(),
    content=(
      #|["fs.mbt", "stub.c", "dir.mbt", "utils.mbt", "dir_test.mbt", "eof_test.mbt", "moon.pkg.json", "seek_test.mbt", "mkdir_test.mbt", "access_test.mbt", "create_test.mbt", "read_all_test.mbt", "realpath_test.mbt", "pkg.generated.mbti", "text_file_test.mbt"]
    ),
  )
}

///|
test "as_dir" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(_) {
    let dir_file = @fs.open("src/fs", mode=ReadOnly)
    defer dir_file.close()
    guard dir_file.kind() is Directory
    let dir = dir_file.as_dir()
    defer dir.close()
    let list = dir.read_all()
    list.sort()
    for file in list {
      let path = b"src/fs/" + file
      let kind = @fs.open(path, mode=ReadOnly).kind()
      assert_eq(kind, @fs.kind(path))
      log.write_string("\{@bytes_util.ascii_to_string(file)}: \{kind}\n")
    }
  })
  inspect(
    log.to_string(),
    content=(
      #|fs.mbt: Regular
      #|stub.c: Regular
      #|dir.mbt: Regular
      #|utils.mbt: Regular
      #|dir_test.mbt: Regular
      #|eof_test.mbt: Regular
      #|moon.pkg.json: Regular
      #|seek_test.mbt: Regular
      #|mkdir_test.mbt: Regular
      #|access_test.mbt: Regular
      #|create_test.mbt: Regular
      #|read_all_test.mbt: Regular
      #|realpath_test.mbt: Regular
      #|pkg.generated.mbti: Regular
      #|text_file_test.mbt: Regular
      #|
    ),
  )
}

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
  inspect(log.to_string(), content="15")
}
