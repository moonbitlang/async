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
struct Options {
  contains : String?
}

///|
fn line_prefix(line_no : Int) -> String {
  let n = if line_no < 10 { "0\{line_no}" } else { "\{line_no}" }
  "L\{n}: "
}

///|
async fn process_lines(
  name : String,
  input : &@io.Reader,
  output : &@io.Writer,
  options : Options,
  show_name~ : Bool,
) -> Unit {
  let mut line_no = 1
  while input.read_until("\n") is Some(line) {
    let keep = match options.contains {
      None => true
      Some(pattern) => line.contains(pattern)
    }
    if keep {
      if show_name {
        output..write_text(name).write_text(":")
      }
      output
      ..write_text(line_prefix(line_no))
      ..write_text(line)
      .write_text("\n")
    }
    line_no += 1
  }
}

///|
async fn process_input(
  path : String,
  output : &@io.Writer,
  options : Options,
  show_name~ : Bool,
) -> Unit {
  if path == "-" {
    process_lines("stdin", @stdio.stdin, output, options, show_name~)
  } else {
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    process_lines(path, file, output, options, show_name~)
  }
}

///|
async fn main {
  let matches = @argparse.Command(
    "line_processing",
    about=(
      #|Line-based stream processing example.
      #|Use "-" to read from stdin.
      #|Input is processed incrementally via read_until("\\n").
    ),
    options=[
      OptionArg(
        "contains",
        short='c',
        about="only output lines that contain PATTERN",
      ),
    ],
    positionals=[
      PositionArg(
        "file",
        about="file to process",
        num_args=@argparse.ValueRange(lower=0),
      ),
    ],
  ).parse()
  let options : Options = {
    contains: match matches.values {
      { "contains": [pattern], .. } => Some(pattern)
      _ => None
    },
  }
  let inputs = match matches.values {
    { "file": files, .. } if !files.is_empty() => files
    _ => ["-"]
  }
  let show_name = inputs.length() > 1
  let out = @io.BufferedWriter::new(@stdio.stdout, size=16 * 1024)
  for path in inputs {
    process_input(path, out, options, show_name~)
  }
  out.flush()
}
