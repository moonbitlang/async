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
async test "MemoryReader basic" {
  let log = []
  let r = @io.MemoryReader() <| w => {
    for data in ["abcd", "1234", "xyzw"] {
      log.push("writing \{data}")
      w.write(data)
      @async.sleep(150)
    }
  }
  defer r.close()
  while r.read_some() is Some(data) {
    log.push("received \{@utf8.decode(data)}")
  }
  json_inspect(log, content=[
    "writing abcd", "received abcd", "writing 1234", "received 1234", "writing xyzw",
    "received xyzw",
  ])
}

///|
async test "MemoryReader cancel" {
  let log = []
  let r = @io.MemoryReader() <| w => {
    for i = 0; ; i = i + 1 {
      try w.write("#\{i}") catch {
        err => {
          log.push("`write` fail with \{err}")
          raise err
        }
      } noraise {
        _ => log.push("written #\{i} successfully")
      }
    }
  }
  for _ in 0..<3 {
    guard r.read_some() is Some(data) else { break }
    @async.sleep(50)
    log.push("received \{@utf8.decode(data)}")
  }
  r.close()
  @async.sleep(50)
  json_inspect(log, content=[
    "written #0 successfully", "received #0", "written #1 successfully", "received #1",
    "written #2 successfully", "received #2", "`write` fail with Cancelled",
  ])
}

///|
async test "MemoryReader failure" {
  let r = @io.MemoryReader() <| _ => {
    @async.sleep(150)
    raise Failure::Failure("failure")
  }
  defer r.close()
  try r.read_all().text() catch {
    err =>
      inspect(
        err,
        content=(
          #|Failure(failure)
        ),
      )
  } noraise {
    _ => fail("expected failure, but program does not raise any error")
  }
}
