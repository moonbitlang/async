///|
// Copyright 2026 International Digital Economy Academy
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
let payload : String = "alpha\nbeta\ngamma"

///|
fn usage() -> Unit {
  println(
    "usage: pidfd_wait_repro <cat-path> [iterations] [parallelism] [mode]",
  )
  println("  mode 0: @process.spawn with explicit stdin/stdout pipe tasks")
  println("  mode 1: @process.run with explicit stdin/stdout pipe tasks")
}

///|
async fn write_stdin(writer : @process.WriteToProcess) -> Unit {
  defer writer.close()
  writer.write(payload)
}

///|
async fn read_stdout(reader : @process.ReadFromProcess) -> &@io.Data {
  defer reader.close()
  reader.read_all()
}

///|
async fn spawn_once(cat : String) -> Unit {
  let (stdin, writer) = @process.write_to_process()
  let (reader, stdout) = @process.read_from_process()
  @async.with_task_group() <| group => {
    group.spawn_bg(allow_failure=true, () => write_stdin(writer))
    let output = group.spawn(() => read_stdout(reader))
    let process = @process.spawn(
      group,
      cat,
      [],
      stdin~,
      stdout~,
      cancel_handler=@process.hard_cancel(),
    )
    let code = process.wait()
    ignore(output.wait())
    if code != 0 {
      fail("@process.spawn child exited with \{code}")
    }
  }
}

///|
async fn run_once(cat : String) -> Unit {
  let (stdin, writer) = @process.write_to_process()
  let (reader, stdout) = @process.read_from_process()
  @async.with_task_group() <| group => {
    group.spawn_bg(allow_failure=true, () => write_stdin(writer))
    let output = group.spawn(() => read_stdout(reader))
    let code = @process.run(
      cat,
      [],
      stdin~,
      stdout~,
      cancel_handler=@process.hard_cancel(),
    )
    ignore(output.wait())
    if code != 0 {
      fail("@process.run child exited with \{code}")
    }
  }
}

///|
async fn run_batch(cat : String, count : Int, mode : Int) -> Unit {
  @async.with_task_group() <| group => {
    for _ in 0..<count {
      group.spawn_bg(() => {
        match mode {
          0 => spawn_once(cat)
          1 => run_once(cat)
          _ => fail("unsupported mode \{mode}")
        }
      })
    }
  }
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    fail("missing cat path")
  }
  let cat = args[1]
  let iterations = if args.length() > 2 {
    @string.parse_int(args[2])
  } else {
    1000
  }
  let parallelism = if args.length() > 3 {
    @string.parse_int(args[3])
  } else {
    1
  }
  let mode = if args.length() > 4 { @string.parse_int(args[4]) } else { 0 }
  if iterations <= 0 || parallelism <= 0 {
    fail("iterations and parallelism must be positive")
  }
  println(
    "pidfd_wait_repro: cat=\{cat} iterations=\{iterations} parallelism=\{parallelism} mode=\{mode}",
  )
  let progress = if iterations < 1000 { iterations } else { 1000 }
  for done = 0; done < iterations; {
    let remaining = iterations - done
    let batch = if remaining < parallelism { remaining } else { parallelism }
    run_batch(cat, batch, mode)
    let next = done + batch
    if next % progress == 0 || next == iterations {
      println("pidfd_wait_repro progress \{next}/\{iterations}")
    }
    continue next
  }
  println("pidfd_wait_repro done")
}
