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
pub(all) enum Signal {
  SIGINT = 0
  SIGTERM = 1
  SIGHUP = 2
  SIGBREAK = 3
} derive(Debug)

///|
pub fn Signal::to_int(signal : Signal) -> Int {
  match signal {
    SIGINT => @event_loop._SIGINT
    SIGTERM => @event_loop._SIGTERM
    SIGHUP => @event_loop._SIGHUP
    SIGBREAK => @event_loop._SIGBREAK
  }
}

///|
pub fn set_global_cancellation_signals(signals : ReadOnlyArray[Signal]) -> Unit {
  @event_loop.set_global_cancellation_signals(signals.map(sig => sig.to_int()))
}
