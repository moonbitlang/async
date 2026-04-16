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
async test "basic create" {
  let path = "_build/basic_create_test"
  {
    let w = @fs.create(path, sync=Full)
    defer w.close()
    w.write(b"abcd\n")
  }
  let result = {
    let r = @fs.open(path, mode=ReadOnly)
    defer r.close()
    r.read_all().text()
  }
  @fs.remove(path)
  inspect(
    result,
    content=(
      #|abcd
      #|
    ),
  )
}

///|
async test "create or append" {
  let path = "_build/create_append_test"
  async fn add_data(data) {
    let w = @fs.open(
      path,
      mode=WriteOnly,
      create_mode=OpenOrCreate,
      sync=Full,
      append=true,
    )
    defer w.close()
    w.write(data)
  }

  add_data(b"abcd")
  add_data(b"efgh")
  let result = {
    let r = @fs.open(path, mode=ReadOnly)
    defer r.close()
    r.read_all().text()
  }
  @fs.remove(path)
  inspect(result, content="abcdefgh")
}

///|
async test "wrapper test" {
  let path = "_build/fs_wrapper_test"
  @fs.write_file(path, b"abcd", create_mode=CreateOrTruncate)
  let result = @fs.read_file(path).text()
  @fs.remove(path)
  inspect(result, content="abcd")
}

///|
async test "create_mode test" {
  let path = "_build/create_exclusive_test"
  @async.with_task_group(group => {
    for create_mode in [@fs.OpenExisting, @fs.TruncateExisting] {
      assert_true((try? @fs.open(path, mode=WriteOnly, create_mode~)) is Err(_))
    }
    {
      let file = @fs.create(path, allow_existing=false)
      defer file.close()
      group.add_defer(() => @fs.remove(path))
      file.write("abcd")
    }
    inspect(@fs.read_file(path).text(), content="abcd")
    assert_true((try? @fs.create(path, allow_existing=false)) is Err(_))
    assert_true(
      (try? @fs.open(path, mode=WriteOnly, create_mode=CreateNew)) is Err(_),
    )
    {
      let file = @fs.open(path, mode=WriteOnly, create_mode=OpenExisting)
      defer file.close()
      file.write("AB")
    }
    inspect(@fs.read_file(path).text(), content="ABcd")
    {
      let file = @fs.open(path, mode=WriteOnly, create_mode=OpenOrCreate)
      defer file.close()
      file.write("XY")
    }
    inspect(@fs.read_file(path).text(), content="XYcd")
    {
      let file = @fs.open(path, mode=WriteOnly, create_mode=CreateOrTruncate)
      defer file.close()
      file.write("12")
    }
    inspect(@fs.read_file(path).text(), content="12")
    {
      let file = @fs.open(path, mode=WriteOnly, create_mode=TruncateExisting)
      defer file.close()
      file.write("34")
    }
    inspect(@fs.read_file(path).text(), content="34")
  })
}
