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
async fn main {
  let mutex1 = @async.Mutex()
  let mutex2 = @async.Mutex()
  @async.with_task_group <| group => {
    group.spawn_bg() <| () => {
      mutex1.acquire()
      defer mutex1.release()
      println("task 1 acquired mutex 1")
      @async.pause()
      mutex2.acquire()
      defer mutex2.release()
      println("task 1 acquired mutex 2")
    }
    group.spawn_bg() <| () => {
      mutex2.acquire()
      defer mutex2.release()
      println("task 2 acquired mutex 2")
      @async.pause()
      mutex1.acquire()
      defer mutex1.release()
      println("task 1 acquired mutex 1")
    }
  }
  println("program completed")
}
