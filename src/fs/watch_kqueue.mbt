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
priv struct WatchedFile {
  fd : @fd_util.Fd
  kind : @fd_util.FileKind
  dev : UInt64
  ino : UInt64
  children : Map[String, @fd_util.Fd]
}

///|
priv struct KqueueWatcher {
  watcher : @event_loop.IoHandle
  watched : Map[@fd_util.Fd, WatchedFile]
  pending_events : Set[FsEvent]
  mut waiter : @coroutine.Coroutine?

  async fn new(String) -> KqueueWatcher
}

///|
async fn KqueueWatcher::new(path : String) -> KqueueWatcher {
  ...
}

///|
impl WatcherImpl for KqueueWatcher with close(self) {
  self.watcher.close()
  for _, file in self.watched {
    @fd_util.close(file.fd, kind=file.kind, context="") catch {
      _ => ()
    }
  }
}

///|
impl WatcherImpl for KqueueWatcher with wait(self) {
  ...
}
