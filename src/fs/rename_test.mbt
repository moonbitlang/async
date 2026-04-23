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
async test "rename basic" {
  let old_path = "_build/rename_basic_test_old"
  let new_path = "_build/rename_basic_test_new"
  let file = @fs.open(
    old_path,
    mode=WriteOnly,
    create_mode=CreateOrTruncate,
    sync=Full,
  )
  defer file.close()
  file.write("abcd")
  inspect(@fs.read_file(old_path).text(), content="abcd")
  @fs.rename(old_path, new_path)
  inspect(@fs.read_file(new_path).text(), content="abcd")
  file.write_at(b"ABCD", position=0)
  inspect(@fs.read_file(new_path).text(), content="ABCD")
  inspect(@fs.exists(old_path), content="false")
  @fs.remove(new_path)
}
