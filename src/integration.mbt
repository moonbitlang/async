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
/// This function is used for integration of `moonbitlang/async`
/// into the MoonBit toolchain, do not call directly.
#coverage.skip
pub fn run_async_main(main : async () -> Unit raise) -> Unit {
  @event_loop.with_event_loop(() => main()) catch {
    _err =>
      // TODO: output the error to stderr
      panic()
  }
}
