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
async test "mkdir" {
  @fs.mkdir("mkdir_test", permission=0o755)
  @fs.write_file("mkdir_test/file", "", create=0o644)
  let result = @fs.readdir("mkdir_test", sort=true)
  @fs.remove("mkdir_test/file")
  @fs.rmdir("mkdir_test")
  inspect(result, content="[\"file\"]")
}

///|
async test "rmdir recursive" {
  @fs.mkdir("rmdir_test", permission=0o755)
  @fs.write_file("rmdir_test/file", "", create=0o644)
  @fs.mkdir("rmdir_test/inner", permission=0o755)
  @fs.write_file("rmdir_test/inner/file", "", create=0o644)
  let _ = @process.run("ln", ["-s", "../../target", "rmdir_test/symlink"])
  let result = try? @fs.rmdir("rmdir_test")
  @fs.rmdir("rmdir_test", recursive=true)
  assert_true(result is Err(_))
}
