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
using @event_loop {type FileIdentity}

///|
priv struct WatchedFile {
  wd : @fd_util.Fd
  file_id : FileIdentity
  paths : Set[(FileIdentity, String)]
  is_dir : Bool
  children : Map[String, FileIdentity]
  mut modified : Bool
  dirty_children : Map[String, FileIdentity]
}

///|
priv trait WatcherBackend {
  fn close(Self) -> Unit
  async fn wait(Self) -> Unit
  async fn add_file(
    Self,
    StringView,
    is_dir~ : Bool,
    file_id~ : FileIdentity,
    context~ : String,
  ) -> @fd_util.Fd
  fn remove_file(Self, @fd_util.Fd, context~ : String) -> Unit raise
}

///|
/// A file system watcher for watching changes in a directory.
struct Watcher {
  mut backend : &WatcherBackend?
  root_id : FileIdentity
  base_path : String
  watched : Map[FileIdentity, WatchedFile]
  pending_remove : Set[FileIdentity]
  ignored_paths : (String) -> Bool
  mut event_count : Int
  mut synchronize_task : @coroutine.Coroutine?
}

///|
pub fn Watcher::close(self : Watcher) -> Unit {
  if self.backend is Some(backend) {
    self.backend = None
    backend.close()
  }
  if self.synchronize_task is Some(task) {
    task.cancel()
  }
}

///|
#cfg(platform="windows")
fn Watcher::new_backend(
  self : Watcher,
  root : @event_loop.IoHandle,
  root_id~ : FileIdentity,
  debounce_timeout~ : Int,
  max_debounce_delay~ : Int,
  context~ : String,
) -> &WatcherBackend {
  ignore(context)
  WindowsWatcher(self, root, root_id~, debounce_timeout~, max_debounce_delay~)
}

///|
#cfg(not(platform="windows"))
fn Watcher::new_backend(
  self : Watcher,
  root : @event_loop.IoHandle,
  root_id~ : FileIdentity,
  debounce_timeout~ : Int,
  max_debounce_delay~ : Int,
  context~ : String,
) -> &WatcherBackend raise {
  ignore(root_id)
  root.close()
  match @event_loop.platform {
    Linux =>
      InotifyWatcher(self, debounce_timeout~, max_debounce_delay~, context~)
      as &WatcherBackend
    MacOS =>
      KqueueWatcher(self, debounce_timeout~, max_debounce_delay~, context~)
      as &WatcherBackend
    Windows => panic()
  }
}

///|
/// Create a new file system watcher that watches the directory `path` recursively.
/// Currently only recursive directory watching is supported.
///
/// When files are created, removed, modified or renamed inside `path`,
/// the watcher will get notified and report events for the change.
/// New files will be watched automatically, and removed files will be unwatched automatically.
///
/// File system events often come in batch.
/// For example, removing a directory recursively will result in several removal event in a row.
/// By default `Watcher` will perform debouncing internally:
/// when many events are happening in sequence, instead of immediately return on the first event,
/// `Watcher::wait_any` will wait until no event is happening
/// within the last `debounce_timeout` ms (defaults to 20ms),
/// or if `max_debounce_delay` ms (defaults to 200ms) has elapsed since the first event.
///
/// `ignored_paths`, if present, can be used to filter out paths that the user don't want to watch.
/// When a file or directory is going to be watched, its path
/// (relative to root of watched tree, using `/` as path separator) will be supplied to `ignored_paths`.
/// If `ignored_paths` return `true`, the file or directory will be ignored.
/// When a directory is ignored, all files/directories within it are also ignored.
/// So to ignore a single directory,
/// `ignored_paths` only need to handle paths of the files inside that ignored directory.
///
/// Currently, the behavior when `path` itself is renamed or removed is undefined.
pub async fn Watcher::Watcher(
  path : String,
  debounce_timeout? : Int = 20,
  max_debounce_delay? : Int = 200,
  ignored_paths? : (String) -> Bool = _ => false,
) -> Watcher {
  let context = "@fs.Watcher()"
  let path = path.trim_end(chars="/")
  let path = if path is "" { "/" } else { path.to_owned() }
  let (root_file, root_id) = @event_loop.open(
    path,
    if @event_loop.platform is Windows {
      3
    } else {
      0
    },
    create=0,
    append=false,
    sync=0,
    mode=0,
    context~,
  )
  guard root_file.kind() is Directory else {
    root_file.close()
    raise @os_error.OSError(@os_error.errno_ENOTDIR, context~)
  }
  let self = {
    backend: None,
    root_id,
    base_path: path,
    watched: {},
    pending_remove: Set([]),
    ignored_paths,
    event_count: 0,
    synchronize_task: None,
  }
  try {
    let backend = self.new_backend(
      root_file,
      root_id~,
      debounce_timeout~,
      max_debounce_delay~,
      context~,
    )
    self.backend = Some(backend)
    let root_wd = backend.add_file(path, is_dir=true, file_id=root_id, context~)
    let root = {
      wd: root_wd,
      file_id: root_id,
      paths: Set([]),
      is_dir: true,
      children: {},
      modified: true,
      dirty_children: {},
    }
    self.watched[root_id] = root
    self.synchronize_tree(context~)
    self.event_count = 0
    self
  } catch {
    err => {
      self.close()
      raise err
    }
  }
}

///|
fn rel_path(parent : String, name : String) -> String {
  if parent is "" {
    name
  } else {
    "\{parent}/\{name}"
  }
}

///|
/// Wait for any change in the watched tree
/// since the last `wait_any` call or watcher creation.
pub async fn Watcher::wait_any(self : Watcher) -> Unit {
  let context = "@fs.Watcher::wait()"
  guard self.backend is Some(backend) else {
    raise Failure::Failure("watcher already closed")
  }
  if self.synchronize_task is Some(task) {
    task.wait()
  }
  while self.event_count <= 0 {
    backend.wait()
    self.synchronize_tree(context~)
  }
  self.event_count = 0
  while self.pending_remove.iter().next() is Some(file_id) {
    self.pending_remove.remove(file_id)
    let file = self.watched[file_id]
    guard file.paths.is_empty() else { continue }
    if file.is_dir {
      for child in file.children.keys() {
        self.remove_file_at(file, child)
      }
    }
    self.watched.remove(file_id)
    backend.remove_file(file.wd, context~)
  }
}

///|
fn WatchedFile::is_clean(file : WatchedFile) -> Bool {
  !file.modified && file.dirty_children.is_empty()
}

///|
async fn Watcher::get_file_at(
  self : Watcher,
  file_id~ : FileIdentity,
  is_dir~ : Bool,
  path~ : String,
  context~ : String,
) -> WatchedFile {
  if self.watched.get(file_id) is Some(existing) {
    return existing
  }

  let full_path = "\{self.base_path}/\{path}"

  guard self.backend is Some(backend) else {
    raise Failure::Failure("watcher already closed")
  }
  let wd = backend.add_file(full_path, is_dir~, file_id~, context~)
  let new_file = {
    wd,
    file_id,
    paths: Set([]),
    is_dir,
    children: {},
    modified: is_dir, // new directory need rescan
    dirty_children: {},
  }
  self.watched[file_id] = new_file
  new_file
}

///|
async fn Watcher::add_file_at(
  self : Watcher,
  dir : WatchedFile,
  name : String,
  is_dir~ : Bool,
  file_id~ : FileIdentity,
  path~ : String,
  context~ : String,
) -> Unit {
  if (self.ignored_paths)(path) {
    return
  }
  if dir.children.get(name) is Some(curr_id) {
    if curr_id == file_id {
      return
    } else {
      self.remove_file_at(dir, name)
    }
  }
  self.event_count += 1
  let location = (dir.file_id, name)
  let file = self.get_file_at(path~, is_dir~, file_id~, context~)
  dir.children[name] = file.file_id
  file.paths.add(location)
  if !file.is_clean() {
    dir.dirty_children[name] = file.file_id
  }
}

///|
fn Watcher::remove_file_at(
  self : Watcher,
  dir : WatchedFile,
  name : String,
) -> Unit {
  let curr_id = dir.children.get(name)
  guard curr_id is Some(curr_id) else { return }
  let path = (dir.file_id, name)
  dir.children.remove(name)
  dir.dirty_children.remove(name)
  let curr = self.watched[curr_id]
  curr.paths.remove(path)
  if curr.paths.is_empty() {
    self.pending_remove.add(curr_id)
  }
}

///|
async fn Watcher::scan_dir(
  self : Watcher,
  dir : WatchedFile,
  path~ : String,
  context~ : String,
) -> Unit {
  let removed_children = dir.children.copy()
  let dir_obj = opendir_aux("\{self.base_path}/\{path}", context~)
  defer dir_obj.close()
  while dir_obj.next_aux(include_special=false, include_hidden=true, context~)
        is Some(ent) {
    let new_file_id = { ..dir.file_id, file_id: ent.file_id }
    self.add_file_at(
      dir,
      ent.name,
      is_dir=ent.is_dir,
      file_id=new_file_id,
      path=rel_path(path, ent.name),
      context~,
    ) catch {
      @os_error.OSError(_) as err if err.is_ENOENT() => continue
      err => raise err
    }
    removed_children.remove(ent.name)
  }
  for name in removed_children.keys() {
    self.event_count += 1
    self.remove_file_at(dir, name)
  }
}

///|
async fn Watcher::synchronize_tree(self : Watcher, context~ : String) -> Unit {
  if self.synchronize_task is Some(task) {
    task.wait()
    return
  }
  let task = @coroutine.spawn <| () => {
    defer {
      self.synchronize_task = None
    }
    let root = self.watched[self.root_id]
    while !root.is_clean() {
      self.synchronize_file(root, path="", context~)
    }
  }
  self.synchronize_task = Some(task)
  task.wait()
}

///|
async fn Watcher::synchronize_file(
  self : Watcher,
  file : WatchedFile,
  path~ : String,
  context~ : String,
) -> Unit {
  if file.modified {
    file.modified = false
    if file.is_dir {
      self.scan_dir(file, path~, context~)
    } else {
      self.event_count += 1
    }
  } else if file.dirty_children.iter().next() is Some((name, child_id)) {
    let child = self.watched[child_id]
    try
      self.synchronize_file(child, path=rel_path(path, name), context~)
    catch {
      @os_error.OSError(_) as err if err.is_ENOENT() =>
        self.mark_as_modified(file.file_id)
      err => raise err
    } noraise {
      _ => if child.is_clean() { file.dirty_children.remove(name) }
    }
  }
}

///|
fn Watcher::mark_as_modified(self : Watcher, id : FileIdentity) -> Unit {
  let file = self.watched[id]
  if file.modified {
    return
  }
  file.modified = true
  if !file.dirty_children.is_empty() || id == self.root_id {
    return
  }
  for path in file.paths {
    let (dir, name) = path
    self.add_dirty_child(dir, name, id)
  }
}

///|
fn Watcher::add_dirty_child(
  self : Watcher,
  dir_id : FileIdentity,
  name : String,
  child_id : FileIdentity,
) -> Unit {
  let dir = self.watched[dir_id]
  let was_clean = dir.is_clean()
  dir.dirty_children[name] = child_id
  if was_clean && dir_id != self.root_id {
    for path in dir.paths {
      let (parent, name) = path
      self.add_dirty_child(parent, name, dir_id)
    }
  }
}

///|
fn Watcher::overflow(self : Watcher) -> Unit {
  for file in self.watched.values() {
    file.modified = true
    if file.is_dir {
      for name, id in file.children {
        file.dirty_children[name] = id
      }
    }
  }
}
