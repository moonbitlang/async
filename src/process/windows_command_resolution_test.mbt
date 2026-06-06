///|
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
#cfg(platform="windows")
async test "run bare .exe command" {
  let (exit_code, output) = @process.collect_stdout("where", ["where"])
  inspect(exit_code, content="0")
  inspect(output.text().contains("where.exe"), content="true")
}

///|
#cfg(platform="windows")
async test "run explicit .exe command" {
  let (exit_code, output) = @process.collect_stdout("where.exe", ["where"])
  inspect(exit_code, content="0")
  inspect(output.text().contains("where.exe"), content="true")
}

///|
#cfg(platform="windows")
async test "reject bare .com command" {
  try ignore(@process.collect_stdout("more", ["/?"])) catch {
    _ => inspect(true, content="true")
  } noraise {
    _ => fail("expected bare .com command to fail")
  }
}

///|
#cfg(platform="windows")
async test "run explicit .com command" {
  let (exit_code, _) = @process.collect_stdout("more.com", ["/?"])
  inspect(exit_code, content="0")
}
