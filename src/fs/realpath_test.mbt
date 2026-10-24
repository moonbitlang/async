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
async test "realpath absolute" {
  let rp = @fs.realpath("src/fs/realpath_test.mbt")
  guard! @env.current_dir() is Some(cwd)
  assert_true(rp.has_prefix(cwd))
  inspect(
    rp[cwd.length():].replace_all(old="\\", new="/"),
    content="/src/fs/realpath_test.mbt",
  )
}

///|
// These symlink scenarios are not supported on Windows. Wasm learns the host
// platform at runtime instead of through MoonBit target cfg.
async test "realpath link to absolute" {
  if @event_loop.platform is Windows {
    return
  }
  guard! @env.current_dir() is Some(cwd)
  let path = match cwd {
    [.., '/'] => cwd + "src/fs/realpath_test.mbt"
    _ => cwd + "/src/fs/realpath_test.mbt"
  }
  let link_path = "_build/realpath_test_link_to_absolute.test"
  @fs.symlink(link_path, target=path)
  defer @fs.remove(link_path)
  let rp = @fs.realpath(link_path)
  assert_true(rp.has_prefix(cwd))
  inspect(rp[cwd.length():], content="/src/fs/realpath_test.mbt")
}

///|
async test "realpath link to relative" {
  if @event_loop.platform is Windows {
    return
  }
  guard! @env.current_dir() is Some(cwd)
  let rel_path = "../src/fs/realpath_test.mbt"
  let link_path = "_build/realpath_test_link_to_relative.test"
  @fs.symlink(link_path, target=rel_path)
  defer @fs.remove(link_path)
  let rp = @fs.realpath(link_path)
  assert_true(rp.has_prefix(cwd))
  inspect(rp[cwd.length():], content="/src/fs/realpath_test.mbt")
}

///|
async test "realpath link to dir absolute" {
  guard! @env.current_dir() is Some(cwd)
  let path = match cwd {
    [.., '/'] => cwd + "src/fs"
    _ => cwd + "/src/fs"
  }
  let link_path = "_build/realpath_test_link_to_dir_absolute.test"
  @fs.symlink(link_path, target=path)
  defer @fs.remove(link_path)
  let rp = @fs.realpath(link_path + "/realpath_test.mbt")
  assert_true(rp.has_prefix(cwd))
  inspect(
    rp[cwd.length():].replace_all(old="\\", new="/"),
    content="/src/fs/realpath_test.mbt",
  )
}

///|
async test "realpath link to dir relative" {
  if @event_loop.platform is Windows {
    return
  }
  guard! @env.current_dir() is Some(cwd)
  let rel_path = "../src/fs"
  let link_path = "_build/realpath_test_link_to_dir_relative.test"
  @fs.symlink(link_path, target=rel_path)
  defer @fs.remove(link_path)
  let rp = @fs.realpath(link_path + "/realpath_test.mbt")
  assert_true(rp.has_prefix(cwd))
  inspect(rp[cwd.length():], content="/src/fs/realpath_test.mbt")
}

///|
// wasm realpath comes from the host runtime, which does not preserve the
// extended prefix; only the native backend goes through
// GetFinalPathNameByHandleW.
#cfg(target="native")
async test "realpath keeps the extended prefix when the plain form is ambiguous" {
  // issue #675: Win32 resolution trims the trailing dot of `folder.`, so
  // dropping `\\?\` can reopen a sibling `folder` instead. The prefix must
  // be kept whenever the plain DOS form would resolve differently.
  if !(match @event_loop.platform {
      Windows => true
      _ => false
    }) {
    return
  }
  // tmpdir() is unavailable in some sandboxes; anchor under the project's
  // _build directory and make it absolute through a plain-path realpath call.
  let base = @fs.realpath("_build")
  let root = base + "\\realpath_675_dotted"
  // plain DOS form here; recursive rmdir handles leftovers from failed runs
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @fs.mkdir(root, recursive=true)
  defer @fs.rmdir(root, recursive=true)
  // only the trailing-dot child needs the extended prefix; recursive rmdir
  // joins child paths with `/`, which the extended form does not accept
  let dotted = "\\\\?\\" + root + "\\folder."
  @fs.mkdir(dotted)
  defer {
    for name in @fs.readdir(dotted) {
      @fs.remove(dotted + "\\" + name) catch {
        _ => ()
      }
    }
    @fs.rmdir(dotted) catch {
      _ => ()
      // a plain rmdir would trim the trailing dot and delete the sibling
    }
  }
  @fs.mkdir(root + "\\folder")
  defer @fs.rmdir(root + "\\folder", recursive=true)
  @fs.write_file(dotted + "\\marker", "intended")
  @fs.write_file(root + "\\folder\\marker", "unrelated")
  let resolved = @fs.realpath(dotted)
  assert_true(resolved.has_prefix("\\\\?\\"))
  assert_eq(@fs.read_file(resolved + "\\marker").text(), "intended")
}

///|
async test "realpath still drops the prefix for plain paths" {
  if !(match @event_loop.platform {
      Windows => true
      _ => false
    }) {
    return
  }
  let base = @fs.realpath("_build")
  let root = base + "\\realpath_675_plain"
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @fs.mkdir(root, recursive=true)
  defer @fs.rmdir(root, recursive=true)
  let resolved = @fs.realpath(root)
  assert_false(resolved.has_prefix("\\\\?\\"))
}
