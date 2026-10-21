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
#cfg(not(platform="windows"))
priv struct UnixEventLoopExtra {
  // On MacOS, PID waiting is implemented directly via kqueue, 
  // so we need to separately maintain waiters for each PID.
  pids : Map[Int32, @coroutine.Coroutine]
  // On Linux/MacOS, notifications for completion of thread pool job
  // are transferred via a pipe, this buffer is used to read from the pipe.
  completed_jobs_buffer : FixedArray[Int32]
}

///|
#cfg(all(target="native", not(platform="windows")))
type PlatformEventLoopExtra = UnixEventLoopExtra

///|
#cfg(not(platform="windows"))
async fn UnixEventLoopExtra::wait_pid(
  self : Self,
  evloop : EventLoop,
  pid : Int32,
) -> Unit {
  guard! self.pids.get(pid) is None
  self.pids[pid] = @coroutine.current_coroutine()
  defer self.pids.remove(pid)
  evloop.suspend()
}
