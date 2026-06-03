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
extern "C" fn WindowsWatcher::event_buffer_size() -> Int = "moonbitlang_async_watcher_event_buffer_size"

///|
#cfg(platform="windows")
#external
priv type WindowsWatcherEvent

///|
#cfg(platform="windows")
#borrow(buf)
extern "C" fn WindowsWatcher::get_os_event(
  buf : FixedArray[Byte],
  offset : Int,
) -> WindowsWatcherEvent = "moonbitlang_async_watcher_get_event"

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherEvent::get_size(event : Self) -> Int = "moonbitlang_async_watcher_event_get_size"

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherEvent::is_modify(event : Self) -> Bool = "moonbitlang_async_watcher_event_is_modify_event"

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherEvent::get_path_len(event : Self) -> Int = "moonbitlang_async_watcher_event_get_path_len"

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherEvent::get_path(event : Self) -> @c_buffer.Buffer = "moonbitlang_async_watcher_event_get_path"

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherEvent::get_file_id(event : Self) -> UInt64 = "moonbitlang_async_watcher_event_get_file_id"

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherEvent::get_parent_file_id(event : Self) -> UInt64 = "moonbitlang_async_watcher_event_get_parent_file_id"

///|
#cfg(platform="windows")
async fn WindowsWatcher::event_handler(self : WindowsWatcher) -> Unit {
  defer self.root.close()
  let context = "@fs.Watcher::wait()"
  let buf = FixedArray::make(WindowsWatcher::event_buffer_size(), b'\x00')
  for ;; {
    let n = self.root.read_dir_changes(buf, context~)
    self.debounce_timer.refresh()
    if n is 0 {
      // overflow
      for file_id, file in self.watcher.watched {
        if file.is_dir {
          self.watcher.mark_as_modified(file_id)
        }
      }
      continue
    }
    let mut offset = 0
    while offset < n {
      let event = WindowsWatcher::get_os_event(buf, offset)
      let size = event.get_size()
      if size is 0 {
        offset = n
      } else {
        offset += size
      }
      let file_id = if WindowsWatcher::has_ReadDirectoryChangesExW() {
        if event.is_modify() {
          event.get_file_id()
        } else {
          event.get_parent_file_id()
        }
      } else {
        let path = @os_string.decode(event.get_path(), len=event.get_path_len())
        let path = if event.is_modify() {
          path[:]
        } else {
          for i in path.length()>..0 {
            if path[i] is ('/' | '\\') {
              break path[:i]
            }
          } nobreak {
            path
          }
        }
        let (file, file_info) = @event_loop.open(
          "\{self.watcher.base_path}\\\{path}",
          0,
          create=0,
          append=false,
          sync=0,
          mode=0,
          context~,
        )
        file.close()
        file_info.file_id()
      }
      let file_id = { dev_id: self.dev_id, file_id }
      if self.watcher.watched.get(file_id) is Some(file) {
        if !(event.is_modify() && file.is_dir) {
          self.watcher.mark_as_modified(file_id)
        }
      }
    }
    if self.waiter is Some(coro) {
      coro.wake()
    }
  }
}
