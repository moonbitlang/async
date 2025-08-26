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
fn String::to_ascii(str : String) -> Bytes {
  Bytes::makei(str.length(), i => str.unsafe_charcode_at(i).to_byte())
}

///|
fn main {
  @async.with_event_loop(fn(_) {
    try {
      let args = @env.args()
      match args {
        [] | [_] => @pipe.stdout.write_reader(@pipe.stdin)
        [_, .. files] =>
          for file in files {
            if file == "-" {
              @pipe.stdout.write_reader(@pipe.stdin)
            } else {
              let file = @fs.open(file.to_ascii(), mode=ReadOnly)
              @pipe.stdout.write_reader(file)
            }
          }
      }
    } catch {
      err => @pipe.stderr.write(err.to_string().to_ascii())
    }
  }) catch {
    _ => ()
  }
}
