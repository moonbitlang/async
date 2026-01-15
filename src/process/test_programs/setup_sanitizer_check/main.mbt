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
fn Json::get_or_add(
  input : Json,
  key : String,
  update : () -> Json,
) -> Json raise {
  guard input is Object(map) else { fail("invalid moon.pkg.json") }
  map.get_or_init(key, update)
}

///|
#cfg(platform="windows")
let sanitizer_flags = "/Z7 /fsanitize=address"

///|
#cfg(not(platform="windows"))
let sanitizer_flags = "-fsanitize=address -g -fno-omit-frame-pointer"

///|
async fn main {
  fn exclude(path : String) {
    match path {
      "./target" | "./_build" | "./examples/target" | "./examples/_build" => true
      "./src/process/test_programs/dump_env" =>
        // This program may be run in an (almost) empty environment,
        // ASAN will not work with some linking related variables missing
        true
      _ => false
    }
  }

  @fs.walk(".", exclude~, (path, files) => for file in files {
    guard file is "moon.pkg.json" else {  }
    let full_path = "\{path}/\{file}"
    let content = @json.parse(@fs.read_file(full_path).text())
    let link = content.get_or_add("link", () => {})
    let native = link.get_or_add("native", () => {})
    guard native is Object(native) else { fail("invalid moon.pkg.json") }
    native["cc-flags"] = Json::string(sanitizer_flags)
    native["stub-cc-flags"] = Json::string(sanitizer_flags)
    @fs.write_file(full_path, content.stringify())
  })
}
