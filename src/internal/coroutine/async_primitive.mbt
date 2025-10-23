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

/// Low-level primitive for suspending async execution.
/// This function allows a coroutine to suspend itself and register
/// continuation callbacks for both success and error cases.
/// The callback function receives two continuations:
/// - ok_cont: called to resume execution with a successful result
/// - err_cont: called to resume execution with an error
/// This is an internal primitive used by higher-level async operations.
async fn[T, E : Error] async_suspend(
  cb : ((T) -> Unit, (E) -> Unit) -> Unit,
) -> T raise E = "%async.suspend"

/// Low-level primitive for running async functions.
/// This function executes an async function that cannot raise errors.
/// It is used internally by the coroutine system to run async code
/// within the scheduler context.
fn run_async(f : async () -> Unit noraise) = "%async.run"
