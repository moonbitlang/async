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
async test "basic seek" {
  let path = "basic_seek_test"
  // initialize
  {
    let w = @fs.create(path, permission=0o644, sync=Full)
    defer w.close()
    inspect(w.size(), content="0")
    w.write(b"abcdef")
    inspect(w.size(), content="6")
  }
  // first read
  {
    let r = @fs.open(path, mode=ReadOnly)
    defer r.close()
    inspect(r.size(), content="6")
    inspect(r.read_all().text(), content="abcdef")
  }
  // update content
  {
    let w = @fs.open(path, mode=WriteOnly)
    defer w.close()
    ignore(w.seek(-2, mode=FromEnd))
    inspect(w.curr_pos(), content="4")
    w.write(b"56")
    ignore(w.seek(2, mode=FromStart))
    inspect(w.curr_pos(), content="2")
    w.write(b"34")
    ignore(w.seek(-4, mode=Relative))
    inspect(w.curr_pos(), content="0")
    w.write(b"12")
  }
  // read content
  {
    let r = @fs.open(path, mode=ReadOnly)
    defer r.close()
    inspect(r.read_all().text(), content="123456")
  }
  @fs.remove(path)
}
