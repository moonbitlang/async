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
priv struct InotifyWatchedDirectory {
  mut rel_path : String
  mut full_path : String
  children : Map[String, @fd_util.Fd?]
}

///|
fn InotifyWatchedDirectory::child_rel_path(
  dir : InotifyWatchedDirectory,
  name : String,
) -> String {
  if dir.rel_path is "" {
    name
  } else {
    "\{dir.rel_path}/\{name}"
  }
}

///|
fn InotifyWatchedDirectory::child_full_path(
  dir : InotifyWatchedDirectory,
  name : String,
) -> String {
  "\{dir.full_path}/\{name}"
}

///|
priv struct InotifyWatcher {
  root_path : String
  watcher : @event_loop.IoHandle
  watched : Map[@fd_util.Fd, InotifyWatchedDirectory]
  pending_events : Set[FsEvent]
  mut err : Error?
  mut waiter : @coroutine.Coroutine?
  mut event_processor : @coroutine.Coroutine?
}

///|
extern "C" fn InotifyWatcher::new_ffi() -> @fd_util.Fd = "moonbitlang_async_inotify_create"

///|
async fn InotifyWatcher::InotifyWatcher(path : String) -> InotifyWatcher {
  let watcher = InotifyWatcher::new_ffi()
  if !@fd_util.fd_is_valid(watcher) {
    @os_error.check_errno("@fs.Watcher::new(\{path.escape()})")
  }
  let root_wd = InotifyWatcher::add_dir_ffi(watcher, @os_string.encode(path))
  if !@fd_util.fd_is_valid(root_wd) {
    @os_error.check_errno("@fs.Watcher::new(\{path.escape()})")
  }
  let self = {
    root_path: path.trim_end(chars="/").to_owned(),
    watcher: @event_loop.IoHandle::from_fd(watcher, kind=Unknown),
    watched: {},
    waiter: None,
    err: None,
    pending_events: Set::new(),
    event_processor: None,
  }
  try {
    let root_dir = { rel_path: "", full_path: self.root_path, children: {} }
    self.watched[root_wd] = root_dir
    self.scan_dir(root_dir, context="@fs.Watcher::new()")
    self.pending_events.clear()
    self.event_processor = Some(
      @coroutine.spawn(() => {
        self.process_events() catch {
          err => {
            self.err = Some(err)
            raise err
          }
        }
      }),
    )
    self
  } catch {
    err => {
      self.close()
      raise err
    }
  }
}

///|
impl WatcherImpl for InotifyWatcher with close(self) {
  if self.event_processor is Some(coro) {
    coro.cancel()
  }
  if self.waiter is Some(coro) {
    coro.wake()
  }
  self.watcher.close()
}

///|
impl WatcherImpl for InotifyWatcher with wait(self) {
  if self.err is Some(err) {
    raise err
  }
  guard self.waiter is None
  if self.pending_events.length() is 0 {
    let coro = @coroutine.current_coroutine()
    self.waiter = Some(coro)
    defer {
      self.waiter = None
    }
    @coroutine.suspend()
  }
  guard self.pending_events.iter().next() is Some(first_event) else {
    guard self.err is Some(err) else { abort("watcher already closed") }
    raise err
  }
  self.pending_events.remove(first_event)
  first_event
}

///|
fn InotifyWatcher::emit_event(self : InotifyWatcher, event : FsEvent) -> Unit {
  self.pending_events.add(event)
  if self.waiter is Some(coro) {
    coro.wake()
  }
}

///|
#borrow(path)
extern "C" fn InotifyWatcher::add_dir_ffi(
  watcher : @fd_util.Fd,
  path : @os_string.OsString,
) -> Int = "moonbitlang_async_inotify_add_dir"

///|
async fn InotifyWatcher::scan_dir(
  self : InotifyWatcher,
  dir : InotifyWatchedDirectory,
  context~ : String,
) -> Unit {
  let removed_children = dir.children.copy()
  for child in readdir(dir.full_path) {
    removed_children.remove(child)
    self.emit_create(dir, child, context~)
  }
  for removed_child in removed_children.keys() {
    self.emit_remove(dir, removed_child, context~)
  }
}

///|
async fn InotifyWatcher::emit_create(
  self : InotifyWatcher,
  parent : InotifyWatchedDirectory,
  name : String,
  context~ : String,
) -> Unit {
  if parent.children.contains(name) {
    self.emit_remove(parent, name, context~)
  }
  self.emit_event(Create(parent.child_rel_path(name)))
  self.add_file(parent, name, context~)
}

///|
async fn InotifyWatcher::add_file(
  self : InotifyWatcher,
  parent : InotifyWatchedDirectory,
  name : String,
  context~ : String,
) -> Unit {
  let rel_path = parent.child_rel_path(name)
  let full_path = parent.child_full_path(name)
  let file = @event_loop.open_detached(
    full_path,
    0,
    create=0,
    append=false,
    sync=0,
    mode=0,
    context~,
  )
  let fd = file.fd()
  let kind = file.kind()
  defer (@fd_util.close(fd, kind~, context="") catch { _ => () })
  if kind is Directory {
    let wd = InotifyWatcher::add_dir_ffi(
      self.watcher.fd(),
      @os_string.encode(full_path),
    )
    if !@fd_util.fd_is_valid(wd) {
      @os_error.check_errno("\{context}: add_dir(\{full_path.escape()})")
    }
    let dir = { rel_path, full_path, children: {} }
    self.watched[wd] = dir
    parent.children[name] = Some(wd)
    let dir_obj = Directory::from_fd(fd)
    while dir_obj.next_aux(include_hidden=true, include_special=false, context~)
          is Some(ent) {
      self.add_file(dir, ent.name, context~)
    }
  } else {
    parent.children[name] = None
  }
}

///|
extern "C" fn InotifyWatcher::remove_dir_ffi(
  watcher : @fd_util.Fd,
  wd : @fd_util.Fd,
) -> Unit = "moonbitlang_async_inotify_remove_dir"

///|
fn InotifyWatcher::emit_remove(
  self : InotifyWatcher,
  parent : InotifyWatchedDirectory,
  name : String,
  context~ : String,
) -> Unit raise {
  self.emit_event(Remove(parent.child_rel_path(name)))
  self.remove_file(parent, name, context~)
}

///|
fn InotifyWatcher::remove_file(
  self : InotifyWatcher,
  parent : InotifyWatchedDirectory,
  name : String,
  context~ : String,
) -> Unit raise {
  guard parent.children.get(name) is Some(child_wd)
  parent.children.remove(name)
  if child_wd is Some(child_wd) {
    InotifyWatcher::remove_dir_ffi(self.watcher.fd(), child_wd)
    let child_dir = self.watched[child_wd]
    for child in child_dir.children.keys() {
      self.remove_file(child_dir, child, context~)
    }
  }
}

///|
fn InotifyWatcher::rename(
  self : InotifyWatcher,
  src_dir : InotifyWatchedDirectory,
  src_name : String,
  dst_dir : InotifyWatchedDirectory,
  dst_name : String,
) -> Unit {
  let old = src_dir.child_rel_path(src_name)
  let new = dst_dir.child_rel_path(dst_name)
  if dst_dir.children.contains(dst_name) {
    self.emit_event(Remove(new))
  }
  self.emit_event(Rename(old~, new~))
  let child = src_dir.children[src_name]
  dst_dir.children[dst_name] = child
  src_dir.children.remove(src_name)
  if child is Some(child_wd) {
    self.update_path(
      child_wd,
      rel_path=new,
      full_path=dst_dir.child_full_path(dst_name),
    )
  }
}

///|
fn InotifyWatcher::update_path(
  self : InotifyWatcher,
  wd : @fd_util.Fd,
  rel_path~ : String,
  full_path~ : String,
) -> Unit {
  let dir = self.watched[wd]
  dir.rel_path = rel_path
  dir.full_path = full_path
  for child, child_wd in dir.children {
    if child_wd is Some(child_wd) {
      self.update_path(
        child_wd,
        rel_path=dir.child_rel_path(child),
        full_path=dir.child_full_path(child),
      )
    }
  }
}

///|
extern "C" fn InotifyWatcher::event_buffer_size() -> Int = "moonbitlang_async_inotify_event_buffer_size"

///|
#external
priv type InotifyEvent

///|
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
#borrow(buf)
extern "C" fn InotifyWatcher::fetch_os_event(
  watcher : @fd_util.Fd,
  buf : FixedArray[Byte],
) -> Int = "moonbitlang_async_inotify_fetch_event"

///|
extern "C" fn InotifyEvent::get_size(event : InotifyEvent) -> Int = "moonbitlang_async_inotify_event_get_size"

///|
extern "C" fn InotifyEvent::get_wd(event : InotifyEvent) -> @fd_util.Fd = "moonbitlang_async_inotify_event_get_wd"

///|
extern "C" fn InotifyEvent::get_name_len(event : InotifyEvent) -> Int = "moonbitlang_async_inotify_event_get_name_len"

///|
extern "C" fn InotifyEvent::get_name(event : InotifyEvent) -> @c_buffer.Buffer = "moonbitlang_async_inotify_event_get_name"

///|
extern "C" fn InotifyEvent::get_cookie(event : InotifyEvent) -> UInt = "moonbitlang_async_inotify_event_get_cookie"

///|
extern "C" fn InotifyEvent::has_create(event : InotifyEvent) -> Bool = "moonbitlang_async_inotify_event_has_create"

///|
extern "C" fn InotifyEvent::has_remove(event : InotifyEvent) -> Bool = "moonbitlang_async_inotify_event_has_remove"

///|
extern "C" fn InotifyEvent::has_modify(event : InotifyEvent) -> Bool = "moonbitlang_async_inotify_event_has_modify"

///|
extern "C" fn InotifyEvent::has_rename_from(event : InotifyEvent) -> Bool = "moonbitlang_async_inotify_event_has_rename_from"

///|
extern "C" fn InotifyEvent::has_rename_to(event : InotifyEvent) -> Bool = "moonbitlang_async_inotify_event_has_rename_to"

///|
extern "C" fn InotifyEvent::has_overflow(event : InotifyEvent) -> Bool = "moonbitlang_async_inotify_event_has_overflow"

///|
extern "C" fn InotifyEvent::has_ignore(event : InotifyEvent) -> Bool = "moonbitlang_async_inotify_event_has_ignore"

///|
async fn InotifyWatcher::process_events(self : InotifyWatcher) -> Unit {
  let context = "@fs.Watcher::wait()"
  let buf = FixedArray::make(InotifyWatcher::event_buffer_size(), b'\x00')
  let pending_rename_from : Map[UInt, (InotifyWatchedDirectory, String)] = Map::new()
  let pending_rename_to : Map[UInt, (InotifyWatchedDirectory, String)] = Map::new()
  self.watcher.prepare_read()
  for ;; {
    let n = InotifyWatcher::fetch_os_event(self.watcher.fd(), buf)
    if n < 0 {
      @os_error.check_errno(context)
    }
    let n = if n is 0 &&
      (pending_rename_from.length() > 0 || pending_rename_to.length() > 0) {
      // according to `https://lwn.net/Articles/605128/`, the 2ms delay
      // is enough to detect 99.8% of rename events even on heavy load
      @async.sleep(2)
      InotifyWatcher::fetch_os_event(self.watcher.fd(), buf)
    } else {
      n
    }
    if n is 0 {
      for _, item in pending_rename_from {
        let (parent, name) = item
        self.emit_remove(parent, name, context~)
      }
      pending_rename_from.clear()
      for _, item in pending_rename_to {
        let (parent, name) = item
        self.emit_create(parent, name, context~)
      }
      pending_rename_to.clear()
      self.watcher.wait_read()
      continue
    }
    let mut offset = 0
    while offset < n {
      let event = InotifyWatcher::get_os_event(buf, offset)
      offset += event.get_size()
      let wd = event.get_wd()
      if event.has_overflow() {
        for dir in self.watched.values() {
          self.scan_dir(dir, context~)
        }
        self.emit_event(Overflow)
        continue
      }
      if event.has_ignore() {
        continue
      }

      let parent = self.watched[wd]
      guard event.get_name_len() > 1
      let name = @os_string.decode(event.get_name())
      if event.has_create() {
        self.emit_create(parent, name, context~)
      }
      if event.has_remove() {
        self.emit_remove(parent, name, context~)
      }
      if event.has_modify() {
        self.emit_event(Modify(parent.child_rel_path(name)))
      }
      if event.has_rename_from() {
        let cookie = event.get_cookie()
        if pending_rename_to.get(cookie) is Some((dst_dir, dst_name)) {
          self.rename(parent, name, dst_dir, dst_name)
          pending_rename_to.remove(cookie)
        } else {
          pending_rename_from[cookie] = (parent, name)
        }
      }
      if event.has_rename_to() {
        let cookie = event.get_cookie()
        if pending_rename_from.get(cookie) is Some((src_dir, src_name)) {
          self.rename(src_dir, src_name, parent, name)
          pending_rename_from.remove(cookie)
        } else {
          pending_rename_to[cookie] = (parent, name)
        }
      }
    }
  }
}
