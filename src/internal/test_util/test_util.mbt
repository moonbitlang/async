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
#callsite(autofill(loc))
pub async fn[T, E : Error] expect_error_async(
  f : async () -> T raise E,
  loc~ : SourceLoc,
) -> E {
  try f() catch {
    err => err
  } noraise {
    _ => fail("expected error, but no error is raised", loc~)
  }
}

///|
#callsite(autofill(loc))
pub async fn[T, E : Error] assert_raise_async(
  f : async () -> T raise E,
  loc~ : SourceLoc,
) -> Unit {
  try f() catch {
    _ => ()
  } noraise {
    _ => fail("expected error, but no error is raised", loc~)
  }
}
