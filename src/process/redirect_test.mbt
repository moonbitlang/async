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
async test "merge multiple" {
  @async.with_task_group() <| root => {
    let (r, w) = @process.read_from_process(shared=true)
    root.spawn_bg(no_wait=true) <| () => {
      defer r.close()
      inspect(r.read_all().text(), content="abcdefgh")
    }
    @async.with_task_group() <| group => {
      defer w.close()
      @process.spawn(group, shell, ["-c", "\{write_stdout} abcd"], stdout=w, extra_env={
        "LANG": "en_US.UTF-8",
      })
      |> ignore
      @process.spawn(
        group,
        shell,
        ["-c", "sleep 1; \{write_stdout} efgh"],
        stdout=w,
        extra_env={ "LANG": "en_US.UTF-8" },
      )
      |> ignore
    }
  }
}

///|
async test "redirect to file" {
  let cat = cat.wait()
  @async.with_task_group() <| root => {
    let input_file = "_build/process_redirect_test_in.txt"
    let output_file = "_build/process_redirect_test_out.txt"
    root.add_defer(() => @fs.remove(input_file))
    root.add_defer(() => @fs.remove(output_file))
    @fs.write_file(input_file, "abcd")
    let _ = @process.run(
      cat,
      [],
      stdin=@process.redirect_from_file(input_file),
      stdout=@process.redirect_to_file(output_file),
    )
    inspect(@fs.read_file(output_file).text(), content="abcd")
  }
}

///|
async test "merge multiple to file" {
  @async.with_task_group() <| root => {
    let output_file = "_build/process_redirect_merge_multiple_test_out.txt"
    root.add_defer(() => @fs.remove(output_file))
    let w = @process.redirect_to_file(output_file, shared=true)
    @async.with_task_group <| group => {
      defer w.close()
      let _ = @process.spawn(
        group,
        shell,
        ["-c", "\{write_stdout} abcd"],
        stdout=w,
        extra_env={ "LANG": "en_US.UTF-8" },
      )
      let _ = @process.spawn(
        group,
        shell,
        ["-c", "sleep 1; \{write_stdout} efgh"],
        stdout=w,
        extra_env={ "LANG": "en_US.UTF-8" },
      )
    }
    inspect(
      @fs.read_file(output_file).text(),
      content=(
        #|abcdefgh
      ),
    )
  }
}

///|
async test "merge stdout and stderr" {
  @async.with_task_group() <| group => {
    let (r, w) = @process.read_from_process()
    defer r.close()
    let _ = @process.spawn(
      group,
      shell,
      ["-c", "\{write_stdout} abcd; \{write_stderr} efgh"],
      stdout=w,
      stderr=w,
    )
    inspect(r.read_all().text(), content="abcdefgh")
  }
}

///|
async test "merge stdout and stderr to file" {
  @async.with_task_group() <| group => {
    let output_file = "_build/process_redirect_merge_test_out.txt"
    group.add_defer(() => @fs.remove(output_file))
    let w = @process.redirect_to_file(output_file)
    let _ = @process.run(
      shell,
      ["-c", "\{write_stdout} abcd; \{write_stderr} efgh"],
      stdout=w,
      stderr=w,
    )
    inspect(
      @fs.read_file(output_file).text(),
      content=(
        #|abcdefgh
      ),
    )
  }
}

///|
async test "pipe" {
  let log = []
  @async.with_task_group() <| group => {
    let cat = cat.wait()
    let (r1, w1) = @process.write_to_process()
    defer w1.close()
    let (r2, w2) = @process.pipe()
    let (r3, w3) = @process.read_from_process()
    group.spawn_bg() <| () => {
      defer r3.close()
      while r3.read_some() is Some(msg) {
        log.push("received: \{@utf8.decode(msg)}")
      }
    }
    let _ = @process.spawn(group, cat, [], stdin=r1, stdout=w2)
    let _ = @process.spawn(group, cat, [], stdin=r2, stdout=w3)
    log.push("writing: abcd")
    w1.write("abcd")
    @async.sleep(150)
    log.push("writing: xyzw")
    w1.write("xyzw")
  }
  json_inspect(log, content=[
    "writing: abcd", "received: abcd", "writing: xyzw", "received: xyzw",
  ])
}
