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
pub using @job_types {type Job}

///|
/// Submit a native binding Job to the shared blocking worker scheduler.
///
/// Host or system errors raised by the worker skip `finish`. Otherwise,
/// `finish` runs on the event-loop thread while `job` and its structured result
/// remain valid. The Job is freed after `finish` returns or raises.
pub async fn[X] with_job(
  job : @job_types.Job,
  finish : (@job_types.Job, Int) -> X raise,
  context~ : String,
) -> X {
  @event_loop.with_native_job(job, ret => finish(job, ret), context~)
}
