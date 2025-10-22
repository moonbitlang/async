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
/// add a random delay before every test,
/// so that there won't be a lot of timers expiring at the same time,
/// causing inaccurate result
async fn random_delay() -> Unit {
  let rand = match rand_seed.val {
    Some(r) => r
    None => {
      let now = @async.now()
      let seed = @buffer.new()
      for _ in 0..<4 {
        seed.write_int64_le(now)
      }
      let rand = @random.Rand::chacha8(seed=seed.to_bytes())
      rand_seed.val = Some(rand)
      rand
    }
  }
  @async.sleep(rand.int(limit=100))
}

///|
let rand_seed : Ref[@random.Rand?] = @ref.new(None)
