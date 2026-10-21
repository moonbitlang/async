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
#warnings("-alert_internal-result_error_return")
fn from_core_stdio(
  x : @runtime_internal.StdioChannel,
) -> Result[IoHandle, Error] = "%identity"

///|
#warnings("-alert_internal")
pub let stdin : Result[IoHandle, Error] = from_core_stdio(
  @runtime_internal.stdin,
)

///|
#warnings("-alert_internal")
pub let stdout : Result[IoHandle, Error] = from_core_stdio(
  @runtime_internal.stdout,
)

///|
#warnings("-alert_internal")
pub let stderr : Result[IoHandle, Error] = from_core_stdio(
  @runtime_internal.stderr,
)
