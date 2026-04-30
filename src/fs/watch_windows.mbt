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
#valtype
priv struct FileIdentity {
  vol_id : UInt64
  file_id : UInt64
} derive(Eq, Hash)

///|
#cfg(platform="windows")
priv struct WatchedFile {
  mut rc : Int
  kind : @fd_util.FileKind
  id : FileIdentity
  mut rel_path : String
  mut full_path : String
  children : Map[String, FileIdentity]
}

///|
#cfg(platform="windows")
fn WatchedFile::child_rel_path(dir : WatchedFile, name : String) -> String {
  if dir.rel_path is "" {
    name
  } else {
    "\{dir.rel_path}\\\{name}"
  }
}

///|
#cfg(platform="windows")
fn WatchedFile::child_full_path(dir : WatchedFile, name : String) -> String {
  "\{dir.full_path}\\\{name}"
}

///|
#cfg(platform="windows")
priv struct InternalEvent {
  file : WatchedFile
  unlink : Array[(WatchedFile, String)]
  link : Array[(WatchedFile, String)]
  mut modified : Bool
  overflow : Bool
}

///|
#cfg(platform="windows")
struct Watcher {
  watcher : @event_loop.IoHandle
  base_path : String
  root : WatchedFile
  all_files : Map[FileIdentity, WatchedFile]
  pending_events : Map[FileIdentity, InternalEvent]
  mut pending_remove : Set[FileIdentity]
  mut err : Error?
  mut waiter : @coroutine.Coroutine?
  mut event_processor : @coroutine.Coroutine?
}

///|
#cfg(platform="windows")
pub async fn Watcher::Watcher(path : String) -> Watcher {
  let context = "@fs.Watcher::new()"
  let path = path.trim_end(chars="/\\").to_owned()
  let dir = @event_loop.open_detached(
    path,
    // 3 is a special value for directory listing.
    // one special thing about file watching is that
    // we need to set `FILE_FLAG_OVERLAPPED` here
    3,
    create=0,
    append=false,
    sync=0,
    mode=0,
    context~,
  )
  let kind = dir.kind()
  guard kind is Directory else {
    raise @os_error.OSError(@os_error.errno_ENOTDIR, context~)
  }
  let watcher = @event_loop.IoHandle::from_fd(
    dir.fd(),
    kind=Directory,
    is_async=true,
  )
  let root = {
    rc: 1,
    kind,
    id: { vol_id: dir.dev_id(), file_id: dir.file_id() },
    rel_path: "",
    full_path: path,
    children: {},
  }
  let self = {
    watcher,
    base_path: path,
    root,
    all_files: {},
    pending_events: {},
    pending_remove: Set::new(),
    err: None,
    waiter: None,
    event_processor: None,
  }
  self.all_files[root.id] = root
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
  self.scan_directory(root, dir.fd(), emit_event=false, context~) catch {
    err => {
      self.close()
      raise err
    }
  }
  self
}

///|
#cfg(platform="windows")
pub fn Watcher::close(self : Watcher) -> Unit {
  if self.event_processor is Some(coro) {
    coro.cancel()
  }
}

///|
#cfg(platform="windows")
pub async fn Watcher::wait(self : Watcher) -> FsEvent {
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
  guard self.pending_events.iter().next() is Some((id, first_event)) else {
    guard self.err is Some(err) else { abort("watcher already closed") }
    raise err
  }
  if first_event.overflow {
    self.pending_events.remove(id)
    return Overflow
  }
  let new_event = match (first_event.unlink.pop(), first_event.link.pop()) {
    (Some((src, src_name)), Some((dst, dst_name))) => {
      let old = src.child_rel_path(src_name)
      let new = dst.child_rel_path(dst_name)
      Rename(old~, new~)
    }
    (Some((parent, name)), None) => Remove(parent.child_rel_path(name))
    (None, Some((parent, name))) => Create(parent.child_rel_path(name))
    (None, None) => {
      guard first_event.modified
      first_event.modified = false
      Modify(first_event.file.rel_path)
    }
  }
  if first_event.unlink is [] && first_event.link is [] && !first_event.modified {
    self.pending_events.remove(id)
  }
  new_event
}

///|
#cfg(platform="windows")
fn Watcher::get_event_for_id(
  self : Watcher,
  id : FileIdentity,
) -> InternalEvent {
  match self.pending_events.get(id) {
    Some(event) => event
    None => {
      let event = {
        link: [],
        unlink: [],
        modified: false,
        file: self.all_files[id],
        overflow: false,
      }
      self.pending_events[id] = event
      event
    }
  }
}

///|
#cfg(platform="windows")
fn Watcher::add_link(
  self : Watcher,
  id : FileIdentity,
  parent : WatchedFile,
  name : String,
) -> Unit {
  let event = self.get_event_for_id(id)
  event.link.push((parent, name))
}

///|
#cfg(platform="windows")
fn Watcher::del_link(
  self : Watcher,
  id : FileIdentity,
  parent : WatchedFile,
  name : String,
) -> Unit {
  let event = self.get_event_for_id(id)
  event.unlink.push((parent, name))
}

///|
#cfg(platform="windows")
async fn Watcher::scan_directory(
  self : Watcher,
  dir : WatchedFile,
  dir_fd : @fd_util.Fd,
  emit_event~ : Bool,
  context~ : String,
) -> Unit {
  let vol_id = dir.id.vol_id
  let dir_obj = Directory::from_fd(dir_fd)
  let removed_children = dir.children.copy()
  while dir_obj.next_aux(include_hidden=true, include_special=false, context~)
        is Some(ent) {
    removed_children.remove(ent.name)
    let new_file_id = { vol_id, file_id: ent.file_id }
    self.add_file(dir, ent.name, new_file_id, emit_event~, context~)
  }
  for name in removed_children.keys() {
    self.remove_file(dir, name, emit_event~)
  }
}

///|
#cfg(platform="windows")
async fn Watcher::add_file(
  self : Watcher,
  dir : WatchedFile,
  name : String,
  id : FileIdentity,
  emit_event~ : Bool,
  context~ : String,
) -> Unit {
  if dir.children.get(name) is Some(existing) {
    if id == existing {
      return
    }
    self.del_link(existing, dir, name)
  }
  dir.children[name] = id
  if self.all_files.get(id) is Some(existing) {
    existing.rc += 1
    self.update_path(existing, dir.child_rel_path(name))
    if emit_event {
      self.add_link(id, dir, name)
    }
    return
  }
  let file = @event_loop.open_detached(
    dir.child_full_path(name),
    0,
    create=0,
    append=false,
    sync=0,
    mode=0,
    context~,
  )
  let fd = file.fd()
  let kind = file.kind()
  defer (@fd_util.close(fd, kind~, context~) catch { _ => () })
  let new_file = {
    rc: 1,
    kind,
    id,
    rel_path: dir.child_rel_path(name),
    full_path: dir.child_full_path(name),
    children: {},
  }
  self.all_files[id] = new_file
  if emit_event {
    self.add_link(id, dir, name)
  }
  if kind is Directory {
    self.scan_directory(new_file, fd, emit_event=false, context~)
  }
}

///|
#cfg(platform="windows")
fn Watcher::remove_file(
  self : Watcher,
  dir : WatchedFile,
  name : String,
  emit_event~ : Bool,
) -> Unit {
  let id = dir.children[name]
  dir.children.remove(name)
  if emit_event {
    self.del_link(id, dir, name)
  }
  let file = self.all_files[id]
  file.rc -= 1
  if file.rc is 0 {
    self.pending_remove.add(id)
  }
}

///|
#cfg(platform="windows")
fn Watcher::update_path(
  self : Watcher,
  file : WatchedFile,
  new_path : String,
) -> Unit {
  file.rel_path = new_path
  file.full_path = "\{self.base_path}/\{new_path}"
  if file.kind is Directory {
    for child, id in file.children {
      self.update_path(self.all_files[id], file.child_rel_path(child))
    }
  }
}

///|
#cfg(platform="windows")
extern "C" fn Watcher::event_buffer_size() -> Int = "moonbitlang_async_watcher_event_buffer_size"

///|
#cfg(platform="windows")
#external
priv type WindowsWatcherEvent

///|
#cfg(platform="windows")
#borrow(buf)
extern "C" fn Watcher::get_os_event(
  buf : FixedArray[Byte],
  offset : Int,
) -> WindowsWatcherEvent = "moonbitlang_async_watcher_get_event"

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherEvent::get_size(event : Self) -> Int = "moonbitlang_async_watcher_event_get_size"

///|
#cfg(platform="windows")
priv enum WindowsWatcherAction {
  FILE_ACTION_ADDED = 1
  FILE_ACTION_REMOVED = 2
  FILE_ACTION_MODIFIED = 3
  FILE_ACTION_RENAMED_OLD_NAME = 4
  FILE_ACTION_RENAMED_NEW_NAME = 5
}

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherEvent::get_action(
  event : Self,
) -> WindowsWatcherAction = "moonbitlang_async_watcher_event_get_action"

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherEvent::get_name_len(event : Self) -> Int = "moonbitlang_async_watcher_event_get_name_len"

///|
#cfg(platform="windows")
extern "C" fn WindowsWatcherEvent::get_name(event : Self) -> @c_buffer.Buffer = "moonbitlang_async_watcher_event_get_name"

///|
#cfg(platform="windows")
async fn Watcher::event_handler(self : Watcher) -> Unit {
  defer self.watcher.close()
  let context = "@fs.Watcher::wait()"
  let buf = FixedArray::make(Watcher::event_buffer_size(), b'\x00')
  for ;; {
    self.process_events(buf, timeout=None, context~)
    if !self.pending_remove.is_empty() {
      self.process_events(buf, timeout=Some(2), context~)
    }
    if self.waiter is Some(coro) && !self.pending_events.is_empty() {
      coro.wake()
    }
    while !self.pending_remove.is_empty() {
      let prev_pending_remove = self.pending_remove
      self.pending_remove = Set::new()
      for id in prev_pending_remove {
        let file = self.all_files[id]
        guard file.rc is 0 else { continue }
        self.all_files.remove(id)
        if file.kind is Directory {
          for name in file.children.keys() {
            self.remove_file(file, name, emit_event=false)
          }
        }
      }
    }
  }
}

///|
#cfg(platform="windows")
async fn Watcher::process_events(
  self : Watcher,
  buf : FixedArray[Byte],
  timeout~ : Int?,
  context~ : String,
) -> Unit {
  let n = if timeout is Some(t) {
    match
      @async.with_timeout_opt(t, () => {
        self.watcher.read_dir_changes(buf, context~)
      }) {
      None => return
      Some(n) => n
    }
  } else {
    self.watcher.read_dir_changes(buf, context~)
  }
  if n is 0 {
    self.pending_events[self.root.id] = {
      file: self.root,
      link: [],
      unlink: [],
      modified: false,
      overflow: true,
    }
    return
  }
  let mut offset = 0
  while offset < n {
    let event = Watcher::get_os_event(buf, offset)
    let size = event.get_size()
    if size is 0 {
      offset = n
    } else {
      offset += size
    }
    let path = @os_string.decode(event.get_name(), len=event.get_name_len())
    let (parent, name) = self.resolve_path(path)
    match event.get_action() {
      FILE_ACTION_ADDED | FILE_ACTION_RENAMED_NEW_NAME => {
        let file = @event_loop.open_detached(
          "\{self.base_path}\\\{path}",
          0,
          create=0,
          append=false,
          sync=0,
          mode=0,
          context~,
        )
        let fd = file.fd()
        let kind = file.kind()
        defer (@fd_util.close(fd, kind~, context~) catch { _ => () })
        let id = { vol_id: file.dev_id(), file_id: file.file_id() }
        self.add_file(parent, name, id, emit_event=true, context~)
      }
      FILE_ACTION_REMOVED | FILE_ACTION_RENAMED_OLD_NAME =>
        self.remove_file(parent, name, emit_event=true)
      FILE_ACTION_MODIFIED => {
        let id = parent.children[name]
        if !(self.all_files[id].kind is Directory) {
          // `ReadDirectoryChangesW` emit modify events on directories
          // when the directory's content has changed.
          // There will be more precise event on this in recursive watching mode,
          // so ignore modify events on directories.
          let event = self.get_event_for_id(id)
          event.modified = true
        }
      }
    }
  }
}

///|
#cfg(platform="windows")
fn Watcher::resolve_path(
  self : Watcher,
  path : String,
) -> (WatchedFile, String) {
  for dir = self.root, path = path[:] {
    guard path.find_by(c => c is ('/' | '\\')) is Some(index) else {
      break (dir, path.to_owned())
    }
    let name = path[:index].to_owned()
    let rest = path[index + 1:]
    let next_id = dir.children[name]
    continue self.all_files[next_id], rest
  }
}
