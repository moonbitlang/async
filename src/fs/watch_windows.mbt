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
#cfg(platform="windows")
priv struct WindowsWatcher {
  root : @event_loop.IoHandle
  dev_id : UInt64
  watcher : Watcher
  mut event_processor : @coroutine.Coroutine?
  mut err : Error?
  mut waiter : @coroutine.Coroutine?
  debounce_timer : @async.Timer
  max_debounce_delay : Int
}

///|
#cfg(platform="windows")
fn WindowsWatcher::WindowsWatcher(
  watcher : Watcher,
  root : @event_loop.IoHandle,
  root_id~ : FileIdentity,
  debounce_timeout~ : Int,
  max_debounce_delay~ : Int,
) -> WindowsWatcher {
  let self = {
    root,
    dev_id: root_id.dev_id,
    watcher,
    err: None,
    waiter: None,
    event_processor: None,
    debounce_timer: @async.Timer(debounce_timeout),
    max_debounce_delay,
  }
  self.event_processor = Some(
    @coroutine.spawn(() => {
      self.event_handler() catch {
        err => {
          self.err = Some(err)
          if self.waiter is Some(coro) {
            coro.wake()
          }
          raise err
        }
      }
    }),
  )
  self
}

///|
#cfg(platform="windows")
impl WatcherBackend for WindowsWatcher with fn close(self) {
  if self.event_processor is Some(coro) {
    coro.cancel()
  }
}

///|
#cfg(platform="windows")
impl WatcherBackend for WindowsWatcher with fn add_file(
  _self,
  _path,
  is_dir~,
  file_id~,
  context~,
) {
  ignore(is_dir)
  ignore(file_id)
  ignore(context)
  @fd_util.invalid_fd
}

///|
#cfg(platform="windows")
impl WatcherBackend for WindowsWatcher with fn remove_file(_self, _fd, context~) {
  ignore(context)
}

///|
#cfg(platform="windows")
impl WatcherBackend for WindowsWatcher with fn wait(self) {
  if self.err is Some(err) {
    raise err
  }
  guard self.event_processor is Some(_)
  guard self.waiter is None
  let root = self.watcher.watched[self.watcher.root_id]
  while root.is_clean() {
    self.waiter = Some(@coroutine.current_coroutine())
    defer {
      self.waiter = None
    }
    @coroutine.suspend()
    if self.err is Some(err) {
      raise err
    }
  }
  @async.with_timeout(self.max_debounce_delay, () => self.debounce_timer.wait()) catch {
    @async.TimeoutError => ()
    err => raise err
  }
}

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcher::has_ReadDirectoryChangesExW() -> Bool = "moonbitlang_async_has_ReadDirectoryChangesExW"

///|
#cfg(platform="windows")
priv struct WindowsWatcherBuf(@c_buffer.Buffer)

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherBuf::size() -> Int = "moonbitlang_async_watcher_event_buffer_size"

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherBuf::event_size(self : Self, offset : Int) -> Int = "moonbitlang_async_watcher_event_get_size"

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherBuf::is_modify(self : Self, offset : Int) -> Bool = "moonbitlang_async_watcher_event_is_modify_event"

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherBuf::get_path_len(self : Self, offset : Int) -> Int = "moonbitlang_async_watcher_event_get_path_len"

///|
/// Get the offset of path data inside the event
#cfg(platform="windows")
extern "C" fn WindowsWatcherBuf::get_path_offset() -> Int = "moonbitlang_async_watcher_event_get_path_offset"

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherBuf::get_file_id(
  self : Self,
  offset : Int,
) -> UInt64 = "moonbitlang_async_watcher_event_get_file_id"

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherBuf::get_parent_file_id(
  self : Self,
  offset : Int,
) -> UInt64 = "moonbitlang_async_watcher_event_get_parent_file_id"

///|
#cfg(platform="windows")
async fn WindowsWatcher::event_handler(self : WindowsWatcher) -> Unit {
  defer self.root.close()
  let context = "@fs.Watcher::wait()"
  let buf_len = WindowsWatcherBuf::size()
  let buf = WindowsWatcherBuf(@c_buffer.new(buf_len))
  defer buf.0.free()
  for ;; {
    let n = self.root.read_dir_changes(buf.0, buf_len, context~)
    self.debounce_timer.refresh()
    if n is 0 {
      // overflow
      self.watcher.overflow()
      continue
    }
    let mut offset = 0
    while offset < n {
      let size = buf.event_size(offset)
      let file_id : FileIdentity = if WindowsWatcher::has_ReadDirectoryChangesExW() {
        let file_id = if buf.is_modify(offset) {
          buf.get_file_id(offset)
        } else {
          buf.get_parent_file_id(offset)
        }
        { dev_id: self.dev_id, file_id }
      } else {
        let path = @os_string.decode(
          buf.0,
          offset=offset + WindowsWatcherBuf::get_path_offset(),
          len=buf.get_path_len(offset),
        )
        let path = if buf.is_modify(offset) {
          path[:]
        } else {
          for i in path.length()>..0 {
            if path[i] is ('/' | '\\') {
              break path[:i]
            }
          } nobreak {
            ""
          }
        }
        // file change in the root directory
        let (file, file_id) = @event_loop.open(
          "\{self.watcher.base_path}\\\{path}",
          0,
          create=0,
          append=false,
          sync=0,
          mode=0,
          context~,
        )
        file.close()
        file_id
      }
      if self.watcher.watched.get(file_id) is Some(file) {
        if !(buf.is_modify(offset) && file.is_dir) {
          self.watcher.mark_as_modified(file_id)
        }
      }
      if size is 0 {
        offset = n
      } else {
        offset += size
      }
    }
    if self.waiter is Some(coro) {
      coro.wake()
    }
  }
}
