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
async fn main {
  let matches = @argparse.Command(
    "xargs",
    about=(
      #|Run COMMAND with initial arguments ARGS and more arguments read from stdin.
      #|COMMAND will be run once for every line in the input.
    ),
    options=[
      OptionArg(
        "jobs",
        short='j',
        about="limit the max number of parallel jobs to COUNT",
      ),
    ],
    positionals=[
      PositionArg(
        "cmd",
        about="command to run",
        num_args=@argparse.ValueRange::single(),
      ),
      PositionArg(
        "args",
        about="initial arguments for the command",
        num_args=ValueRange(lower=0),
        allow_hyphen_values=true,
      ),
    ],
  ).parse()
  let max_jobs = match matches.values {
    { "jobs": [count], .. } => Some(@async.Semaphore(@string.parse_int(count)))
    _ => None
  }
  guard matches.values is { "cmd": [cmd], .. } else {
    fail("no command specified")
  }
  let args = match matches.values {
    { "args": args, .. } => args
    _ => []
  }
  @async.with_task_group <| group => {
    while @stdio.stdin.read_until("\n") is Some(line) {
      if max_jobs is Some(limit) {
        limit.acquire()
      }
      group.spawn_bg() <| () => {
        defer (if max_jobs is Some(limit) { limit.release() })
        ignore(@process.run(cmd, [..args, line]))
      }
    }
  }
}
