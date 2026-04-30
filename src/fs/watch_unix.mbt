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
/// A file system watcher for monitoring file system changes.
#cfg(not(platform="windows"))
struct Watcher {
  impl_ : &WatcherImpl
}

///|
/// Create a new file system watcher that watches 
/// the directory at `path` recursively.
/// Currently only directory watching is supported.
///
/// New files in the directory and its sub directories
/// will be watched automatically after reported.
/// Files will also be automatically unwatched
/// when they are moved out of the watched directory.
///
/// When the root directory is renamed or deleted,
/// currently no event will be generated,
/// due to limitation of Windows API.
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
/// Wait for and return the next file system event in a watcher.
#cfg(not(platform="windows"))
pub async fn Watcher::wait(self : Watcher) -> FsEvent {
  self.impl_.wait()
}
