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
enum TestFile {
  File(String) // content of file
  Dir(Map[String, TestFile])
}

///|
async fn TestFile::instantiate(self : TestFile, path : String) -> Unit {
  match self {
    File(content) => @fs.write_file(path, content, create_mode=CreateOrTruncate)
    Dir(files) => {
      @fs.mkdir(path)
      for name, file in files {
        file.instantiate("\{path}/\{name}")
      }
    }
  }
}

///|
async test "watch basic" {
  let log = []
  @async.with_task_group(group => {
    let path = "_build/watch_basic_test"
    let test_dir = Dir({
      "root_file": File("abcd"),
      "inner_dir": Dir({ "inner_file": File("efgh") }),
    })
    test_dir.instantiate(path)
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(path, recursive=true))
    })

    let watcher = @fs.Watcher(path)
    group.spawn_bg(no_wait=true, () => {
      defer watcher.close()
      for ;; {
        let event = watcher.wait()
        log.push("watcher received: \{@debug.to_string(event)}")
      }
    })
    // 1. modify content of existing file at root
    log.push("writing to root file")
    @fs.write_file("\{path}/root_file", "ABCD", create_mode=OpenExisting)
    @async.sleep(150)

    // 2. modify content of existing file at inner directory
    log.push("writing to inner file")
    @fs.write_file(
      "\{path}/inner_dir/inner_file",
      "EFGH",
      create_mode=OpenExisting,
    )
    @async.sleep(150)

    // 3. create file in root directory
    {
      log.push("creating new file in root directory")
      let file = @fs.create("\{path}/root_file2")
      defer file.close()
      @async.sleep(150)

      // 4. modify content of newly created file at root directory
      log.push("writing to newly created root file")
      file.write("ABCD")
    }
    @async.sleep(150)

    // 5. create file in inner directory
    {
      log.push("creating new file in inner directory")
      let file = @fs.create("\{path}/inner_dir/inner_file2")
      defer file.close()
      @async.sleep(150)

      // 6. modify content of newly created file at inner directory
      log.push("writing to newly created inner file")
      file.write("EFGH")
    }
    @async.sleep(150)

    // 7. remove a file in root directory
    log.push("removing file in root directory")
    @fs.remove("\{path}/root_file")
    @async.sleep(150)

    // 8. remove a file in inner directory
    log.push("removing file in inner directory")
    @fs.remove("\{path}/inner_dir/inner_file2")
    @async.sleep(150)

    // 9. remove inner directory recursively
    log.push("removing inner directory")
    @fs.rmdir("\{path}/inner_dir", recursive=true)
    @async.sleep(150)

    // 10. create new inner directory
    log.push("creating new directory in root directory")
    @fs.mkdir("\{path}/inner_dir")
    @async.sleep(150)

    // 11. create new file in newly created inner directory
    {
      log.push("creating new file in inner directory")
      let file = @fs.create("\{path}/inner_dir/inner_file")
      defer file.close()
      @async.sleep(150)

      // 12. modify content of newly created file at newly created inner directory
      log.push("writing to newly created inner file")
      file.write("EFGH")
    }
    @async.sleep(150)
  })
  inspect(
    log.join("\n"),
    content=(
      #|writing to root file
      #|watcher received: Modify("root_file")
      #|writing to inner file
      #|watcher received: Modify("inner_dir/inner_file")
      #|creating new file in root directory
      #|watcher received: Create("root_file2")
      #|writing to newly created root file
      #|watcher received: Modify("root_file2")
      #|creating new file in inner directory
      #|watcher received: Create("inner_dir/inner_file2")
      #|writing to newly created inner file
      #|watcher received: Modify("inner_dir/inner_file2")
      #|removing file in root directory
      #|watcher received: Remove("root_file")
      #|removing file in inner directory
      #|watcher received: Remove("inner_dir/inner_file2")
      #|removing inner directory
      #|watcher received: Remove("inner_dir/inner_file")
      #|watcher received: Remove("inner_dir")
      #|creating new directory in root directory
      #|watcher received: Create("inner_dir")
      #|creating new file in inner directory
      #|watcher received: Create("inner_dir/inner_file")
      #|writing to newly created inner file
      #|watcher received: Modify("inner_dir/inner_file")
    ),
  )
}

///|
async test "watch rename within" {
  let log = []
  @async.with_task_group(group => {
    let path = "_build/watch_rename_within_test"
    let test_dir = Dir({
      "root_file": File("abcd"),
      "inner_dir": Dir({ "inner_file": File("efgh") }),
    })
    test_dir.instantiate(path)
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(path, recursive=true))
    })

    let watcher = @fs.Watcher(path)
    group.spawn_bg(no_wait=true, () => {
      defer watcher.close()
      for ;; {
        let event = watcher.wait()
        log.push("watcher received: \{@debug.to_string(event)}")
      }
    })
    // 1. rename within the same directory
    log.push("rename: inner_dir/inner_file => inner_dir/inner_file2")
    @fs.rename("\{path}/inner_dir/inner_file", "\{path}/inner_dir/inner_file2")
    @async.sleep(150)

    // 2. modify file renamed within the same directory
    log.push("writing to inner_dir/inner_file2")
    @fs.write_file(
      "\{path}/inner_dir/inner_file2",
      "efgh",
      create_mode=OpenExisting,
    )
    @async.sleep(150)

    // 3. rename directory
    log.push("rename: inner_dir => inner_dir2")
    @fs.rename("\{path}/inner_dir", "\{path}/inner_dir2")
    @async.sleep(150)

    // 4. modify file within renamed directory
    log.push("writing to inner_dir2/inner_file2")
    @fs.write_file(
      "\{path}/inner_dir2/inner_file2",
      "EFGH",
      create_mode=OpenExisting,
    )
    @async.sleep(150)

    // 5. rename across directory, but within watched tree
    log.push("rename: inner_dir2/inner_file2 => root_file2")
    @fs.rename("\{path}/inner_dir2/inner_file2", "\{path}/root_file2")
    @async.sleep(150)

    // 6. modify file moved across directory but still within watched tree
    log.push("writing to root_file2")
    @fs.write_file("\{path}/root_file2", "EFGH", create_mode=OpenExisting)
    @async.sleep(150)

    // 7. rename file replaces existing file
    log.push("rename root_file2 to replace root_file")
    @fs.rename("\{path}/root_file2", "\{path}/root_file")
    @async.sleep(150)
  })
  inspect(
    log.join("\n"),
    content=(
      #|rename: inner_dir/inner_file => inner_dir/inner_file2
      #|watcher received: Rename(old="inner_dir/inner_file", new="inner_dir/inner_file2")
      #|writing to inner_dir/inner_file2
      #|watcher received: Modify("inner_dir/inner_file2")
      #|rename: inner_dir => inner_dir2
      #|watcher received: Rename(old="inner_dir", new="inner_dir2")
      #|writing to inner_dir2/inner_file2
      #|watcher received: Modify("inner_dir2/inner_file2")
      #|rename: inner_dir2/inner_file2 => root_file2
      #|watcher received: Rename(old="inner_dir2/inner_file2", new="root_file2")
      #|writing to root_file2
      #|watcher received: Modify("root_file2")
      #|rename root_file2 to replace root_file
      #|watcher received: Remove("root_file")
      #|watcher received: Rename(old="root_file2", new="root_file")
    ),
  )
}

///|
async test "watch rename inout test" {
  let log = []
  @async.with_task_group(group => {
    let base_path = "_build/watch_rename_inout_test"
    let test_dir = Dir({
      "watched": Dir({
        "root_file": File("abcd"),
        "inner_dir": Dir({ "inner_file": File("efgh") }),
      }),
    })
    test_dir.instantiate(base_path)
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(base_path, recursive=true))
    })
    let watched_path = "\{base_path}/watched"

    let watcher = @fs.Watcher(watched_path)
    group.spawn_bg(no_wait=true, () => {
      defer watcher.close()
      for ;; {
        let event = watcher.wait()
        log.push("watcher received: \{@debug.to_string(event)}")
      }
    })
    // 1. move foreign file inside watched tree
    @fs.write_file("\{base_path}/foreign_file", "1234", create_mode=CreateNew)
    log.push("moving foreign file inside watched tree")
    @fs.rename("\{base_path}/foreign_file", "\{watched_path}/moved_in_file")
    @async.sleep(150)

    // 2. modify moved in file
    log.push("writing to moved_in_file")
    @fs.write_file(
      "\{watched_path}/moved_in_file",
      "5678",
      create_mode=OpenExisting,
    )
    @async.sleep(150)

    // 3. move foreign directory inside watched tree
    let foreign_dir = Dir({ "foreign_file": File("xyzw") })
    foreign_dir.instantiate("\{base_path}/foreign_dir")
    log.push("moving foreign directory inside watched tree")
    @fs.rename("\{base_path}/foreign_dir", "\{watched_path}/moved_in_dir")
    @async.sleep(150)

    // 4. modify file within moved in directory
    log.push("writing to moved_in_dir/foreign_file")
    @fs.write_file(
      "\{watched_path}/moved_in_dir/foreign_file",
      "XYZW",
      create_mode=OpenExisting,
    )
    @async.sleep(150)

    // 5. move file outside watched tree
    log.push("moving file outside watched tree")
    @fs.rename("\{watched_path}/moved_in_file", "\{base_path}/moved_out_file")
    @async.sleep(150)

    // 6. modify moved out file
    log.push("writing to moved_out_file")
    @fs.write_file(
      "\{base_path}/moved_out_file",
      "1234",
      create_mode=OpenExisting,
    )
    @async.sleep(150)

    // 7. remove moved out file
    log.push("removing moved out file")
    @fs.remove("\{base_path}/moved_out_file")
    @async.sleep(150)

    // 8. move directory outside watched tree
    log.push("moving directory outside watched tree")
    @fs.rename("\{watched_path}/moved_in_dir", "\{base_path}/moved_out_dir")
    @async.sleep(150)

    // 9. modify file inside moved out directoy
    log.push("writing to moved_out_dir/foreign_file")
    @fs.write_file(
      "\{base_path}/moved_out_dir/foreign_file",
      "xyzw",
      create_mode=OpenExisting,
    )
    @async.sleep(150)

    // 10. remove moved out file
    log.push("removing moved out directory")
    @fs.rmdir("\{base_path}/moved_out_dir", recursive=true)
    @async.sleep(150)

    // 11. moved in file overwrites existing file
    log.push("renaming foreign file to replace root_file")
    @fs.write_file("\{base_path}/foreign_file", "1234", create_mode=CreateNew)
    @fs.rename("\{base_path}/foreign_file", "\{watched_path}/root_file")
    @async.sleep(150)

    // 12. moved in directory cannot replace existing directory: forbidden by OS
  })
  inspect(
    log.join("\n"),
    content=(
      #|moving foreign file inside watched tree
      #|watcher received: Create("moved_in_file")
      #|writing to moved_in_file
      #|watcher received: Modify("moved_in_file")
      #|moving foreign directory inside watched tree
      #|watcher received: Create("moved_in_dir")
      #|writing to moved_in_dir/foreign_file
      #|watcher received: Modify("moved_in_dir/foreign_file")
      #|moving file outside watched tree
      #|watcher received: Remove("moved_in_file")
      #|writing to moved_out_file
      #|removing moved out file
      #|moving directory outside watched tree
      #|watcher received: Remove("moved_in_dir")
      #|writing to moved_out_dir/foreign_file
      #|removing moved out directory
      #|renaming foreign file to replace root_file
      #|watcher received: Remove("root_file")
      #|watcher received: Create("root_file")
    ),
  )
}
