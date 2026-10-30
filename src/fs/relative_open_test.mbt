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
#cfg(any(target="native", target="wasm"))
async test "relative open" {
  let old_path = "_build/relative_open_test"
  let new_path = "_build/relative_open_test_renamed"
  @fs.mkdir(old_path)
  defer (@fs.rmdir(old_path, recursive=true) catch { _ => () })
  defer (@fs.rmdir(new_path, recursive=true) catch { _ => () })
  @fs.write_file("\{old_path}/file", "abcd")
  let dir = @fs.opendir(old_path)
  defer dir.close()
  json_inspect(dir.read_all(), content=["file"])
  @fs.rename(old_path, new_path)
  match @test_util.expect_error_async(() => @fs.read_file("\{old_path}/file")) {
    @os_error.OSError(_) as err => assert_true(err.is_ENOENT())
    err =>
      raise Failure("incorrect error when accessing out-dated old path: \{err}")
  }
  @fs.mkdir(old_path)
  @fs.write_file("\{old_path}/file", "replacement")
  inspect(@fs.read_file("\{new_path}/file").text(), content="abcd")
  let file = dir.open("file", mode=ReadOnly)
  defer file.close()
  inspect(file.read_all().text(), content="abcd")
}

///|
#cfg(any(target="native", target="wasm"))
async test "relative remove" {
  let old_path = "_build/relative_remove_test"
  let new_path = "_build/relative_remove_test_renamed"
  @fs.mkdir(old_path)
  defer (@fs.rmdir(old_path, recursive=true) catch { _ => () })
  defer (@fs.rmdir(new_path, recursive=true) catch { _ => () })
  @fs.write_file("\{old_path}/file", "abcd")
  let dir = @fs.opendir(old_path)
  defer dir.close()
  json_inspect(dir.read_all(), content=["file"])
  @fs.rename(old_path, new_path)
  match @test_util.expect_error_async(() => @fs.read_file("\{old_path}/file")) {
    @os_error.OSError(_) as err => assert_true(err.is_ENOENT())
    err =>
      raise Failure("incorrect error when accessing out-dated old path: \{err}")
  }
  @fs.mkdir(old_path)
  @fs.write_file("\{old_path}/file", "replacement")
  inspect(@fs.read_file("\{new_path}/file").text(), content="abcd")
  dir.remove("file")
  assert_false(@fs.exists("\{new_path}/file"))
  inspect(@fs.read_file("\{old_path}/file").text(), content="replacement")
}

///|
#cfg(any(target="native", target="wasm"))
async test "relative remove rejects parent traversal and absolute paths" {
  let root = "_build/relative_remove_validation_test"
  @fs.mkdir("\{root}/base/nested", recursive=true)
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file("\{root}/victim", "keep")
  let absolute = @fs.realpath("\{root}/victim")
  let dir = @fs.opendir("\{root}/base")
  defer dir.close()
  for path in ["../victim", "nested/../../victim", absolute] {
    match @test_util.expect_error_async(() => dir.remove(path)) {
      Failure(_) => ()
      err => raise Failure("expected filename validation failure, got \{err}")
    }
    inspect(@fs.read_file("\{root}/victim").text(), content="keep")
  }
}

///|
#cfg(any(target="native", target="wasm"))
async test "relative remove normalizes paths like relative open" {
  let root = "_build/relative_remove_normalization_test"
  @fs.mkdir("\{root}/nested", recursive=true)
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file("\{root}/nested/file", "keep")
  let dir = @fs.opendir(root)
  defer dir.close()
  let path = match @event_loop.platform {
    Windows => ".\\nested//./file"
    Linux | MacOS => ".//nested/./file"
  }
  dir.remove(path)
  assert_false(@fs.exists("\{root}/nested/file"))
}
