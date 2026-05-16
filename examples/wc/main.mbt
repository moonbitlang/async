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
async fn main {
  let matches = @argparse.Command(
    "wc",
    about="Count lines, words, and bytes in a file.",
    positionals=[
      PositionArg(
        "file",
        about="file to count",
        num_args=@argparse.ValueRange(lower=1, upper=1),
      ),
    ],
  ).parse()
  match matches.values {
    { "file": [file], .. } => {
      let text = @fs.read_file(file).text()
      // count lines
      let mut lines : Int = 0
      for ch in text {
        if ch == '\n' {
          lines += 1
        }
      }
      // count words (state machine on chars)
      let (words, _) = text.fold(init=(0, true), fn(acc, ch) {
        let (count, in_space) = acc
        let is_ws = ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
        if is_ws {
          (count, true)
        } else if in_space {
          (count + 1, false)
        } else {
          (count, false)
        }
      })
      // count bytes
      let bytes = @utf8.encode(text).length()
      println("\{lines} \{words} \{bytes} \{file}")
    }
    _ => fail("expected exactly one file argument")
  }
}
