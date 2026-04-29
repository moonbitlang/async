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
#valtype
priv struct FileIdentity {
  dev_id : UInt64
  file_id : UInt64
} derive(Eq, Hash)

///|
#cfg(not(platform="windows"))
priv struct KqueueWatchedFile {
  fd : @fd_util.Fd
  kind : @fd_util.FileKind
  id : FileIdentity
  mut rel_path : String
  mut full_path : String
  children : Map[String, @fd_util.Fd]
}

///|
#cfg(not(platform="windows"))
fn KqueueWatchedFile::child_rel_path(
  dir : KqueueWatchedFile,
  name : String,
) -> String {
  if dir.rel_path is "" {
    name
  } else {
    "\{dir.rel_path}/\{name}"
  }
}

///|
#cfg(not(platform="windows"))
fn KqueueWatchedFile::child_full_path(
  dir : KqueueWatchedFile,
  name : String,
) -> String {
  "\{dir.full_path}/\{name}"
}

///|
#cfg(not(platform="windows"))
priv enum KqueueInternalEvent {
  Create(parent~ : KqueueWatchedFile, name~ : String, file_id~ : FileIdentity?)
  Remove(parent~ : KqueueWatchedFile, name~ : String, file_id~ : FileIdentity?)
  Rename(
    src~ : KqueueWatchedFile,
    src_name~ : String,
    dst~ : KqueueWatchedFile,
    dst_name~ : String
  )
  Modify(String)
}

///|
#cfg(not(platform="windows"))
priv struct KqueueWatcher {
  watcher : @event_loop.IoHandle
  watched : Map[@fd_util.Fd, KqueueWatchedFile]
  root_path : String
  pending_events : @deque.Deque[KqueueInternalEvent]
  pending_rename : Map[FileIdentity, KqueueInternalEvent]
  event_buffer : FixedArray[Byte]
}

///|
#cfg(not(platform="windows"))
extern "C" fn KqueueWatcher::new_ffi() -> @fd_util.Fd = "moonbitlang_async_kqueue_watcher_create"

///|
#cfg(not(platform="windows"))
extern "C" fn KqueueWatcher::event_buffer_size() -> Int = "moonbitlang_async_kqueue_watcher_buffer_size"

///|
#cfg(not(platform="windows"))
async fn KqueueWatcher::KqueueWatcher(path : String) -> KqueueWatcher {
  let context = "@fs.Watcher::new()"
  let watcher = KqueueWatcher::new_ffi()
  if !@fd_util.fd_is_valid(watcher) {
    @os_error.check_errno("@fs.Watcher::new(\{path.escape()})")
  }
  let path = path.trim_end(chars="/").to_owned()
  let self = {
    watcher: @event_loop.IoHandle::from_fd(watcher, kind=Unknown),
    watched: {},
    root_path: path,
    pending_events: @deque.Deque::new(),
    pending_rename: {},
    event_buffer: FixedArray::make(KqueueWatcher::event_buffer_size(), 0),
  }
  try {
    let _ = self.add_file(path, rel_path="", context~)
    while self.pending_events.pop_front() is Some(event) {
      ignore(self.process_event(event, context~))
    }
    self.pending_rename.clear()
    self
  } catch {
    err => {
      self.close()
      raise err
    }
  }
}

///|
#cfg(not(platform="windows"))
impl WatcherImpl for KqueueWatcher with close(self) {
  self.watcher.close()
  for _, file in self.watched {
    @fd_util.close(file.fd, kind=file.kind, context="") catch {
      _ => ()
    }
  }
}

///|
#cfg(not(platform="windows"))
#external
priv type KqueueEvent

///|
#cfg(not(platform="windows"))
#borrow(buf)
extern "C" fn KqueueWatcher::get_os_event(
  buf : FixedArray[Byte],
  index : Int,
) -> KqueueEvent = "moonbitlang_async_kqueue_watcher_get_event"

///|
/// Return value:
/// - positive => number of bytes written
/// - zero => no more event available currently
/// - negative => error
#cfg(not(platform="windows"))
#borrow(buf)
extern "C" fn KqueueWatcher::fetch_os_event(
  watcher : @fd_util.Fd,
  buf : FixedArray[Byte],
) -> Int = "moonbitlang_async_kqueue_watcher_fetch_event"

///|
#cfg(not(platform="windows"))
extern "C" fn KqueueEvent::fd(event : KqueueEvent) -> @fd_util.Fd = "moonbitlang_async_kqueue_watcher_event_get_fd"

///|
#cfg(not(platform="windows"))
extern "C" fn KqueueEvent::has_modify(event : KqueueEvent) -> Bool = "moonbitlang_async_kqueue_watcher_event_has_modify"

///|
#cfg(not(platform="windows"))
impl WatcherImpl for KqueueWatcher with wait(self) {
  let context = "@fs.Watcher::wait()"
  self.watcher.prepare_read()
  if self.pending_events.is_empty() {
    self.try_fetch_events(context~)
    while self.pending_events.is_empty() {
      self.watcher.wait_read()
      self.try_fetch_events(context~)
    }
  }

  let actual_event = match self.pending_events.pop_front().unwrap() {
    Create(file_id=Some(file_id), ..) | Remove(file_id=Some(file_id), ..) if self.pending_rename.get(
        file_id,
      )
      is Some(event) => {
      self.pending_rename.remove(file_id)
      event
    }
    event => event
  }
  self.process_event(actual_event, context~)
}

///|
#cfg(not(platform="windows"))
async fn KqueueWatcher::process_event(
  self : KqueueWatcher,
  event : KqueueInternalEvent,
  context~ : String,
) -> FsEvent {
  match event {
    Create(parent~, name~, file_id=_) => {
      let full_path = parent.child_full_path(name)
      let rel_path = parent.child_rel_path(name)
      parent.children[name] = self.add_file(full_path, rel_path~, context~)
      Create(parent.child_rel_path(name))
    }
    Remove(parent~, name~, file_id=_) => {
      self.remove_file(parent, name, context~)
      Remove(parent.child_rel_path(name))
    }
    Rename(src~, src_name~, dst~, dst_name~) => {
      let old = src.child_rel_path(src_name)
      let new = dst.child_rel_path(dst_name)
      self.rename(src, src_name, dst, dst_name)
      Rename(old~, new~)
    }
    Modify(path) => Modify(path)
  }
}

///|
#cfg(not(platform="windows"))
async fn KqueueWatcher::try_fetch_events(
  self : KqueueWatcher,
  context~ : String,
) -> Unit {
  for ;; {
    let n = KqueueWatcher::fetch_os_event(self.watcher.fd(), self.event_buffer)
    if n < 0 {
      @os_error.check_errno(context)
    }
    if n is 0 {
      break
    }
    for i in 0..<n {
      let event = KqueueWatcher::get_os_event(self.event_buffer, i)
      let fd = event.fd()
      guard self.watched.get(fd) is Some(file) else { continue }
      if event.has_modify() {
        if file.kind is Directory {
          self.scan_dir(file, context~)
        } else {
          self.emit_event(Modify(file.rel_path))
        }
      }
    }
  }
}

///|
#cfg(not(platform="windows"))
fn KqueueWatcher::emit_event(
  self : KqueueWatcher,
  event : KqueueInternalEvent,
) -> Unit {
  self.pending_events.push_back(event)
}

///|
#cfg(not(platform="windows"))
async fn KqueueWatcher::scan_dir(
  self : KqueueWatcher,
  dir : KqueueWatchedFile,
  context~ : String,
) -> Unit {
  let removed_children = dir.children.copy()
  let dir_obj = Directory::from_fd(dir.fd)
  let mut restart = true
  while dir_obj.next_aux(
          include_special=false,
          include_hidden=true,
          restart~,
          context~,
        )
        is Some(ent) {
    restart = false
    removed_children.remove(ent.name)
    let new_file_id = { dev_id: dir.id.dev_id, file_id: ent.file_id }
    if dir.children.get(ent.name) is Some(fd) {
      let existing = self.watched[fd]
      if new_file_id == existing.id {
        continue
      }
      self.emit_remove(existing.id, parent=dir, name=ent.name)
      self.emit_create(new_file_id, parent=dir, name=ent.name)
    } else {
      self.emit_create(new_file_id, parent=dir, name=ent.name)
    }
  }
  for name, removed_file in removed_children {
    self.emit_remove(self.watched[removed_file].id, parent=dir, name~)
  }
}

///|
#cfg(not(platform="windows"))
fn KqueueWatcher::emit_remove(
  self : KqueueWatcher,
  id : FileIdentity,
  parent~ : KqueueWatchedFile,
  name~ : String,
) -> Unit {
  if self.pending_rename.get(id) is Some(prev_event) {
    if prev_event is Create(parent=dst, name=dst_name, ..) {
      self.pending_rename[id] = Rename(
        src=parent,
        src_name=name,
        dst~,
        dst_name~,
      )
    } else {
      // hard link
      self.emit_event(Remove(parent~, name~, file_id=None))
    }
  } else {
    let event : KqueueInternalEvent = Remove(parent~, name~, file_id=Some(id))
    self.pending_rename[id] = event
    self.emit_event(event)
  }
}

///|
#cfg(not(platform="windows"))
fn KqueueWatcher::emit_create(
  self : KqueueWatcher,
  id : FileIdentity,
  parent~ : KqueueWatchedFile,
  name~ : String,
) -> Unit {
  if self.pending_rename.get(id) is Some(prev_event) {
    if prev_event is Remove(parent=src, name=src_name, ..) {
      self.pending_rename[id] = Rename(
        src~,
        src_name~,
        dst=parent,
        dst_name=name,
      )
    } else {
      // hard link
      self.emit_event(Create(parent~, name~, file_id=None))
    }
  } else {
    let event : KqueueInternalEvent = Create(parent~, name~, file_id=Some(id))
    self.pending_rename[id] = event
    self.emit_event(event)
  }
}

///|
#cfg(not(platform="windows"))
extern "C" fn KqueueWatcher::add_file_ffi(
  watcher : @fd_util.Fd,
  fd : @fd_util.Fd,
) -> Int = "moonbitlang_async_kqueue_watcher_add_file"

///|
#cfg(not(platform="windows"))
async fn KqueueWatcher::add_file(
  self : KqueueWatcher,
  path : String,
  rel_path~ : String,
  context~ : String,
) -> @fd_util.Fd {
  let file = @event_loop.open_detached(
    path,
    0,
    create=0,
    append=false,
    sync=0,
    mode=0,
    context~,
  )
  let fd = file.fd()
  let kind = file.kind()
  let dev_id = file.dev_id()
  let file_id = file.file_id()
  if KqueueWatcher::add_file_ffi(self.watcher.fd(), fd) < 0 {
    @fd_util.close(fd, kind~, context~)
    @os_error.check_errno(context)
  }
  let id = { dev_id, file_id }
  let entry = { fd, kind, id, rel_path, full_path: path, children: {} }
  self.watched[fd] = entry
  if kind is Directory {
    let dir = Directory::from_fd(fd)
    while dir.next_aux(include_hidden=true, include_special=false, context~)
          is Some(ent) {
      let full_path = entry.child_full_path(ent.name)
      let rel_path = entry.child_rel_path(ent.name)
      entry.children[ent.name] = self.add_file(full_path, rel_path~, context~)
    }
  }
  fd
}

///|
#cfg(not(platform="windows"))
fn KqueueWatcher::remove_file(
  self : KqueueWatcher,
  dir : KqueueWatchedFile,
  name : String,
  context~ : String,
) -> Unit raise {
  let fd = dir.children[name]
  dir.children.remove(name)
  let entry = self.watched[fd]
  // closing the fd (which must be the last fd pointing to the file description)
  // automatically unregister the event for kqueue
  @fd_util.close(fd, kind=entry.kind, context~)
  self.watched.remove(fd)
  if entry.kind is Directory {
    for child in entry.children.keys() {
      self.remove_file(entry, child, context~)
    }
  }
}

///|
#cfg(not(platform="windows"))
fn KqueueWatcher::rename(
  self : KqueueWatcher,
  src_dir : KqueueWatchedFile,
  src_name : String,
  dst_dir : KqueueWatchedFile,
  dst_name : String,
) -> Unit {
  let child = src_dir.children[src_name]
  dst_dir.children[dst_name] = child
  src_dir.children.remove(src_name)
  self.update_path(self.watched[child], dst_dir.child_rel_path(dst_name))
}

///|
#cfg(not(platform="windows"))
fn KqueueWatcher::update_path(
  self : KqueueWatcher,
  file : KqueueWatchedFile,
  new_path : String,
) -> Unit {
  file.rel_path = new_path
  file.full_path = "\{self.root_path}/\{new_path}"
  if file.kind is Directory {
    for child, fd in file.children {
      self.update_path(self.watched[fd], file.child_rel_path(child))
    }
  }
}
