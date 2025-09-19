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
test "realpath absolute" {
  @async.with_event_loop(fn(_) {
    let rp = @fs.realpath("src/fs/realpath_test.mbt") |> @encoding/utf8.decode
    guard @env.current_dir() is Some(cwd)
    assert_true(rp.has_prefix(cwd))
    inspect(rp[cwd.length():], content="/src/fs/realpath_test.mbt")
  })
}

///|
test "realpath link to absolute" {
  @async.with_event_loop(fn(root) {
    guard @env.current_dir() is Some(cwd)
    let path = match cwd {
      [.., '/'] => cwd + "src/fs/realpath_test.mbt"
      _ => cwd + "/src/fs/realpath_test.mbt"
    }
    let path = @encoding/utf8.encode(path)
    let link_path = b"target/realpath_test_link_to_absolute.test"
    inspect(@process.run("ln", ["-s", path, link_path]), content="0")
    root.add_defer(() => @fs.remove(link_path))
    let rp = @fs.realpath(link_path) |> @encoding/utf8.decode
    assert_true(rp.has_prefix(cwd))
    inspect(rp[cwd.length():], content="/src/fs/realpath_test.mbt")
  })
}

///|
test "realpath link to relative" {
  @async.with_event_loop(fn(root) {
    guard @env.current_dir() is Some(cwd)
    let rel_path = b"../src/fs/realpath_test.mbt"
    let link_path = b"target/realpath_test_link_to_relative.test"
    inspect(@process.run("ln", ["-s", rel_path, link_path]), content="0")
    root.add_defer(() => @fs.remove(link_path))
    let rp = @fs.realpath(link_path) |> @encoding/utf8.decode
    assert_true(rp.has_prefix(cwd))
    inspect(rp[cwd.length():], content="/src/fs/realpath_test.mbt")
  })
}

///|
test "realpath link to dir" {
  @async.with_event_loop(fn(root) {
    guard @env.current_dir() is Some(cwd)
    let rel_path = b"../src/fs"
    let link_path = b"target/realpath_test_link_to_dir.test"
    inspect(@process.run("ln", ["-s", rel_path, link_path]), content="0")
    root.add_defer(() => @fs.remove(link_path))
    let rp = @fs.realpath(link_path + "/realpath_test.mbt")
      |> @encoding/utf8.decode
    assert_true(rp.has_prefix(cwd))
    inspect(rp[cwd.length():], content="/src/fs/realpath_test.mbt")
  })
}
