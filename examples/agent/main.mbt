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
/// A tiny agent example: takes a task from the command line, asks DeepSeek
/// to drive a small loop with three tools (shell, read, write), and prints
/// the final answer.
///
/// Requires the `DEEPSEEK` environment variable to be set to a DeepSeek API
/// key. The model is asked to reply with one JSON object per turn:
///   {"action": "shell" | "read" | "write" | "finish", "args": {...}}

///|
let api_url : String = "https://api.deepseek.com/chat/completions"

///|
let max_steps : Int = 200

///|
/// Path to the MoonBit reference sheet, loaded into the system prompt at startup.
/// Resolved relative to the current working directory (the examples dir).
let moonbit_guide_path : String = "agent/moonbit_guide.md"

///|
/// Protocol & tool description sent to the model on every call.
let protocol_prompt : String =
  #|You are a minimal coding agent. Each turn, reply with exactly ONE JSON
  #|object on a single line and nothing else (no markdown, no code fences,
  #|no prose). The object MUST have keys "action" and "args" exactly:
  #|  {"action": "<name>", "args": {<tool-specific keys>}}
  #|Examples:
  #|  {"action":"shell","args":{"cmd":"ls -la"}}
  #|  {"action":"read","args":{"path":"foo.txt"}}
  #|  {"action":"write","args":{"path":"foo.txt","content":"hello\n"}}
  #|  {"action":"finish","args":{"answer":"done"}}
  #|Tools:
  #|  shell  : args.cmd is passed to `sh -c`; returns exit code + stdout+stderr.
  #|  read   : args.path returns the file contents.
  #|  write  : args.path + args.content overwrites the file. Parent directories
  #|           are NOT auto-created; run `mkdir -p` via shell first if needed.
  #|  finish : args.answer is the final answer; ends the loop.
  #|After every tool call you will receive the result as the next user
  #|message. Keep going until the task is done, then send `finish`.
  #|
  #|The next section is reference material on MoonBit (the language you may be
  #|asked to write or modify). Treat it as authoritative when relevant.
  #|========== MOONBIT GUIDE ==========

///|
fn message(role : String, content : String) -> Json {
  { "role": role, "content": content }
}

///|
/// Look up a field on a JSON object; returns `None` if not an object or not present.
fn field(j : Json, key : String) -> Json? {
  if j is Object(obj) {
    obj.get(key)
  } else {
    None
  }
}

///|
/// Per-call usage record returned alongside the model's text reply, used to
/// observe DeepSeek's prompt-cache behavior turn by turn.
struct Usage {
  cache_hit : Int
  cache_miss : Int
  completion : Int
}

///|
fn field_int(j : Json, key : String) -> Int {
  match field(j, key) {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
}

///|
async fn call_api(
  api_key : String,
  model : String,
  messages : Array[Json],
) -> (String, Usage) {
  let request_body : Json = {
    "model": model,
    "messages": Json::array(messages),
    "stream": false,
  }
  let (resp, body) = @http.post(api_url, request_body, headers={
    "Content-Type": "application/json",
    "Authorization": "Bearer " + api_key,
  })
  let body_text = body.text()
  guard resp.code == 200 else {
    fail("DeepSeek API error \{resp.code}: \{body_text}")
  }
  let parsed = @json.parse(body_text)
  guard field(parsed, "choices") is Some(Array(choices)) else {
    fail("unexpected response: \{body_text}")
  }
  guard choices.length() > 0 else { fail("empty choices in response") }
  guard field(choices[0], "message") is Some(msg) else {
    fail("missing message in choice: \{body_text}")
  }
  guard field(msg, "content") is Some(String(content)) else {
    fail("missing content in message: \{body_text}")
  }
  let usage_json = match field(parsed, "usage") {
    Some(u) => u
    None => Json::object(Map([]))
  }
  let usage = Usage::{
    cache_hit: field_int(usage_json, "prompt_cache_hit_tokens"),
    cache_miss: field_int(usage_json, "prompt_cache_miss_tokens"),
    completion: field_int(usage_json, "completion_tokens"),
  }
  (content, usage)
}

///|
/// Run `sh -c cmd`, capture combined stdout+stderr, and return a string with
/// the exit code prefix. Uses a task group so the read side drains the pipe
/// concurrently with process execution.
async fn tool_shell(cmd : String) -> String {
  let buf = StringBuilder::new()
  let exit_code = @async.with_task_group(group => {
    let (r, w) = @process.read_from_process()
    defer r.close()
    let proc = @process.spawn(group, "sh", ["-c", cmd], stdout=w, stderr=w)
    group.spawn_bg(() => buf.write_string(r.read_all().text()))
    proc.wait()
  })
  "exit=\{exit_code}\n\{buf.to_string()}"
}

///|
async fn dispatch(action : String, args : Json) -> String {
  match action {
    "shell" => {
      guard field(args, "cmd") is Some(String(cmd)) else {
        return "error: shell requires {\"cmd\": string}"
      }
      tool_shell(cmd) catch {
        e => "error running shell: \{e}"
      }
    }
    "read" => {
      guard field(args, "path") is Some(String(path)) else {
        return "error: read requires {\"path\": string}"
      }
      @fs.read_file(path).text() catch {
        e => "error reading \{path}: \{e}"
      }
    }
    "write" => {
      guard field(args, "path") is Some(String(path)) else {
        return "error: write requires {\"path\": string, \"content\": string}"
      }
      guard field(args, "content") is Some(String(content)) else {
        return "error: write requires {\"path\": string, \"content\": string}"
      }
      try {
        @fs.write_file(path, content, create_mode=CreateOrTruncate)
        "ok: wrote \{content.length()} chars to \{path}"
      } catch {
        e => "error writing \{path}: \{e}"
      }
    }
    other => "error: unknown action \"\{other}\""
  }
}

///|
async fn main {
  guard @env.get_env_var("DEEPSEEK") is Some(api_key) && api_key != "" else {
    fail("DEEPSEEK environment variable is not set")
  }
  let argv = @env.args()
  guard argv.length() > 1 else { fail("usage: agent <task description>") }
  let task = argv[1:].join(" ")
  let model = match @env.get_env_var("DEEPSEEK_MODEL") {
    Some(m) if m != "" => m
    _ => "deepseek-chat"
  }
  println("model: \{model}")
  let moonbit_guide = @fs.read_file(moonbit_guide_path).text() catch { _ => "" }
  let system_prompt = protocol_prompt + "\n" + moonbit_guide
  let messages : Array[Json] = [
    message("system", system_prompt),
    message("user", task),
  ]
  let mut total_hit = 0
  let mut total_miss = 0
  let mut total_out = 0
  for step in 0..<max_steps {
    println("--- step \{step + 1} ---")
    let (reply, usage) = call_api(api_key, model, messages)
    total_hit += usage.cache_hit
    total_miss += usage.cache_miss
    total_out += usage.completion
    let pct = if usage.cache_hit + usage.cache_miss > 0 {
      usage.cache_hit * 100 / (usage.cache_hit + usage.cache_miss)
    } else {
      0
    }
    println(
      "usage: hit=\{usage.cache_hit} miss=\{usage.cache_miss} out=\{usage.completion} cache_hit=\{pct}%",
    )
    println("agent: \{reply}")
    messages.push(message("assistant", reply))
    let parsed = @json.parse(reply) catch {
      _ => {
        println("warn: reply was not valid JSON, asking model to retry")
        messages.push(
          message(
            "user", "error: your last reply was not valid JSON. Reply with exactly one JSON object, nothing else.",
          ),
        )
        continue
      }
    }
    guard field(parsed, "action") is Some(String(action)) else {
      messages.push(message("user", "error: missing string field \"action\""))
      continue
    }
    let args = match field(parsed, "args") {
      Some(j) => j
      None => Json::object(Map([]))
    }
    if action == "finish" {
      let answer = match field(args, "answer") {
        Some(String(s)) => s
        _ => "(no answer)"
      }
      println("=== finished: \{answer} ===")
      report_totals(total_hit, total_miss, total_out)
      return
    }
    let result = dispatch(action, args)
    println("tool: \{result}")
    messages.push(message("user", result))
  }
  println("=== max steps (\{max_steps}) exhausted ===")
  report_totals(total_hit, total_miss, total_out)
}

///|
fn report_totals(hit : Int, miss : Int, out : Int) -> Unit {
  let total = hit + miss
  let pct = if total > 0 { hit * 100 / total } else { 0 }
  println(
    "=== total usage: prompt_hit=\{hit} prompt_miss=\{miss} completion=\{out} overall_cache_hit=\{pct}% ===",
  )
}
