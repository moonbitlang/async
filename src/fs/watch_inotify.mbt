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
priv struct InotifyWatcher {
  inotify : @event_loop.IoHandle
  watched : Map[@fd_util.Fd, FileIdentity]
  watcher : Watcher
  mut event_processor : @coroutine.Coroutine?
  mut err : Error?
  mut waiter : @coroutine.Coroutine?
  debounce_timer : @async.Timer
}

///|
#cfg(not(platform="windows"))
extern "C" fn InotifyWatcher::new_ffi() -> @fd_util.Fd = "moonbitlang_async_inotify_create"

///|
#cfg(not(platform="windows"))
fn InotifyWatcher::InotifyWatcher(
  watcher : Watcher,
  context~ : String,
) -> InotifyWatcher raise {
  let inotify_fd = InotifyWatcher::new_ffi()
  if !@fd_util.fd_is_valid(inotify_fd) {
    @os_error.check_errno(context)
  }
  let self = {
    inotify: @event_loop.IoHandle::from_fd(
      inotify_fd,
      kind=Unknown,
      is_async=true,
    ),
    watched: {},
    watcher,
    event_processor: None,
    waiter: None,
    err: None,
    debounce_timer: @async.Timer(20),
  }
  self.event_processor = Some(
    @coroutine.spawn(() => {
      self.process_events() catch {
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
#cfg(not(platform="windows"))
impl WatcherBackend for InotifyWatcher with fn close(self) {
  self.inotify.close()
  if self.event_processor is Some(coro) {
    coro.cancel()
    self.event_processor = None
  }
  if self.waiter is Some(coro) {
    coro.wake()
  }
}

///|
#cfg(not(platform="windows"))
impl WatcherBackend for InotifyWatcher with fn wait(self) {
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
  @async.with_timeout(200, () => self.debounce_timer.wait()) catch {
    @async.TimeoutError => ()
    err => raise err
  }
}

///|
#cfg(not(platform="windows"))
#borrow(path)
extern "C" fn InotifyWatcher::add_file_ffi(
  inotify_fd : @fd_util.Fd,
  path : @os_string.OsString,
  is_dir~ : Bool,
) -> @fd_util.Fd = "moonbitlang_async_inotify_add_file"

///|
#cfg(not(platform="windows"))
impl WatcherBackend for InotifyWatcher with fn add_file(
  self,
  path_str,
  is_dir~,
  file_id~,
  context~,
) {
  let path = @os_string.encode(path_str)
  let wd = InotifyWatcher::add_file_ffi(self.inotify.fd(), path, is_dir~)
  if !@fd_util.fd_is_valid(wd) {
    @os_error.check_errno("\{context}: \{path_str.escape()}")
  }
  self.watched[wd] = file_id
  wd
}

///|
#cfg(not(platform="windows"))
extern "C" fn InotifyWatcher::remove_file_ffi(
  watcher : @fd_util.Fd,
  wd : @fd_util.Fd,
) -> Int = "moonbitlang_async_inotify_remove_file"

///|
#cfg(not(platform="windows"))
impl WatcherBackend for InotifyWatcher with fn remove_file(self, wd, context~) {
  guard self.watched.contains(wd) else {
    // `inotify` sometimes perform auto removal when file is deleted
    return
  }
  self.watched.remove(wd)
  let ret = InotifyWatcher::remove_file_ffi(self.inotify.fd(), wd)
  if ret < 0 {
    @os_error.check_errno(context)
  }
}

///|
#cfg(not(platform="windows"))
extern "C" fn InotifyWatcher::event_buffer_size() -> Int = "moonbitlang_async_inotify_event_buffer_size"

///|
#cfg(not(platform="windows"))
#external
priv type InotifyEvent

///|
#cfg(not(platform="windows"))
#borrow(buf)
extern "C" fn InotifyWatcher::get_os_event(
  buf : FixedArray[Byte],
  offset : Int,
) -> InotifyEvent = "moonbitlang_async_inotify_get_event"

///|
/// Return value:
/// - positive => number of bytes written
/// - zero => no more event available currently
/// - negative => error
#cfg(not(platform="windows"))
#borrow(buf)
extern "C" fn InotifyWatcher::fetch_os_event(
  watcher : @fd_util.Fd,
  buf : FixedArray[Byte],
) -> Int = "moonbitlang_async_inotify_fetch_event"

///|
#cfg(not(platform="windows"))
extern "C" fn InotifyEvent::get_size(event : InotifyEvent) -> Int = "moonbitlang_async_inotify_event_get_size"

///|
#cfg(not(platform="windows"))
extern "C" fn InotifyEvent::get_wd(event : InotifyEvent) -> @fd_util.Fd = "moonbitlang_async_inotify_event_get_wd"

///|
#cfg(not(platform="windows"))
extern "C" fn InotifyEvent::has_relevant_evnet(event : InotifyEvent) -> Bool = "moonbitlang_async_inotify_event_has_relevant_event"

///|
#cfg(not(platform="windows"))
extern "C" fn InotifyEvent::has_overflow(event : InotifyEvent) -> Bool = "moonbitlang_async_inotify_event_has_overflow"

///|
#cfg(not(platform="windows"))
extern "C" fn InotifyEvent::has_ignore(event : InotifyEvent) -> Bool = "moonbitlang_async_inotify_event_has_ignore"

///|
#cfg(not(platform="windows"))
async fn InotifyWatcher::process_events(self : InotifyWatcher) -> Unit {
  let context = "@fs.Watcher::wait()"
  let buf = FixedArray::make(InotifyWatcher::event_buffer_size(), b'\x00')
  self.inotify.prepare_read()
  for ;; {
    let n = InotifyWatcher::fetch_os_event(self.inotify.fd(), buf)
    if n < 0 {
      @os_error.check_errno(context)
    }
    if n is 0 {
      if self.waiter is Some(coro) {
        coro.wake()
      }
      self.inotify.wait_read()
      continue
    }
    self.debounce_timer.refresh()
    let mut offset = 0
    while offset < n {
      let event = InotifyWatcher::get_os_event(buf, offset)
      offset += event.get_size()
      let wd = event.get_wd()
      if event.has_ignore() {
        self.watched.remove(wd)
        continue
      }

      if event.has_overflow() {
        for file_id, file in self.watcher.watched {
          if file.is_dir {
            self.watcher.mark_as_modified(file_id)
          }
        }
        continue
      }

      if event.has_relevant_evnet() {
        let id = self.watched[wd]
        self.watcher.mark_as_modified(id)
      }
    }
  }
}
