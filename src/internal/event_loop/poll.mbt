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
priv type Instance Int

///|
pub(all) enum Events {
  Read = 1
  Write = 2
  ReadWrite = 3
  Error = 4
}

///|
extern "C" fn Instance::new() -> Instance = "moonbitlang_async_poll_create"

///|
extern "C" fn Instance::destroy(self : Instance) = "moonbitlang_async_poll_destroy"

///|
extern "C" fn Instance::register_ffi(
  self : Instance,
  fd : Int,
  events~ : Events,
  oneshot~ : Bool,
) -> Int = "moonbitlang_async_poll_register"

///|
fn Instance::register(
  self : Instance,
  fd : Int,
  events~ : Events,
  oneshot~ : Bool = false,
) -> Unit raise {
  if 0 != self.register_ffi(fd, events~, oneshot~) {
    @os_error.check_errno()
  }
}

///|
extern "C" fn Instance::modify_ffi(
  self : Instance,
  fd : Int,
  events~ : Events,
  oneshot~ : Bool = false,
) -> Int = "moonbitlang_async_poll_modify"

///|
fn Instance::modify(
  self : Instance,
  fd : Int,
  events~ : Events,
  oneshot~ : Bool = false,
) -> Unit raise {
  if 0 != self.modify_ffi(fd, events~, oneshot~) {
    @os_error.check_errno()
  }
}

///|
extern "C" fn Instance::remove_ffi(
  self : Instance,
  fd : Int,
  events~ : Events,
) -> Int = "moonbitlang_async_poll_remove"

///|
fn Instance::remove(self : Instance, fd : Int, events~ : Events) -> Unit raise {
  if 0 != self.remove_ffi(fd, events~) {
    @os_error.check_errno()
  }
}

///|
#external
priv type Event

///|
extern "C" fn get_event(index : Int) -> Event = "moonbitlang_async_event_list_get"

///|
extern "C" fn Event::fd(self : Event) -> Int = "moonbitlang_async_event_get_fd"

///|
extern "C" fn Event::events(self : Event) -> Events = "moonbitlang_async_event_get_events"

///|
extern "C" fn Instance::wait(self : Instance, timeout~ : Int) -> Int = "moonbitlang_async_poll_wait"
