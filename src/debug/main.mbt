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
extern "C" fn fflush(f : UInt64) -> Int = "fflush"

///|
fn[X : Show] log(obj : X) -> Unit {
  println(obj)
  ignore(fflush(0))
}

///|
fn main {
  log("program start")
  @async.with_event_loop(fn(_) {
    log("before open dir")
    let dir_file = @fs.open("src/fs", mode=ReadOnly)
    log("after open dir")
    defer {
      log("before closing dir file")
      dir_file.close()
      log("after closing dir file")
    }
    guard dir_file.kind() is Directory
    log("before as_dir")
    let dir = dir_file.as_dir()
    log("after as_dir")
    defer {
      log("before closing dir")
      dir.close()
      log("after closing dir")
    }
    log("before read all")
    let list = dir.read_all()
    log("after read all")
    list.sort()
    for name in list {
      let name_str = @bytes_util.ascii_to_string(name)
      log("before open(\{name_str})")
      let file = @fs.open(b"src/fs/" + name, mode=ReadOnly)
      defer {
        log("before closing \{name_str}")
        file.close()
        log("after closing \{name_str}")
      }
      log("\{name_str}: \{file.kind()}")
    }
  }) catch {
    err => log(err)
  }
  log("program terminate")
}

