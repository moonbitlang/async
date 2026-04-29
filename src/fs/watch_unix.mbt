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
priv trait WatcherImpl {
  close(Self) -> Unit
  async wait(Self) -> FsEvent
}

///|
#cfg(not(platform="windows"))
struct Watcher {
  impl_ : &WatcherImpl
}

///|
#cfg(not(platform="windows"))
pub async fn Watcher::Watcher(path : String) -> Watcher {
  match @event_loop.platform {
    Linux => { impl_: InotifyWatcher(path) }
    MacOS => { impl_: KqueueWatcher(path) }
    Windows => panic()
  }
}

///|
#cfg(not(platform="windows"))
pub fn Watcher::close(self : Watcher) -> Unit {
  self.impl_.close()
}

///|
#cfg(not(platform="windows"))
pub async fn Watcher::wait(self : Watcher) -> FsEvent {
  self.impl_.wait()
}
