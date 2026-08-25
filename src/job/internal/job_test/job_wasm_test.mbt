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
#unsafe_skip_stub_check
fn make_sleep_job(milliseconds : Int) -> UInt64 = "moonbitlang/async" "thread_pool/make_sleep_job"

///|
async test "runtime-owned Wasm Job uses the shared worker scheduler" {
  assert_false(@async.is_being_cancelled())
  let ret = @job.with_job(
    @job.Job::from_runtime_handle(make_sleep_job(1)),
    (_, ret) => ret,
    context="runtime-owned Wasm Job",
  )
  inspect(ret, content="0")
}
