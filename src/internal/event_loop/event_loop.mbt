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
pub(all) enum Platform {
  Linux = 0
  MacOS = 1
  Windows = 2
}

///|
extern "C" fn get_platform() -> Platform = "moonbitlang_async_get_platform"

///|
pub let platform : Platform = get_platform()

///|
priv struct EventLoop {
  // EventLoop owns the canonical identity for suspended work. Backend adapters
  // translate platform ids such as fd, job id, or pollable id to this id, and
  // `Backend::poll` must return only subscription ids.
  mut subscription_id : Int
  subscriptions : Map[Int, Subscription]
  backend : Backend
}

///|
// `extenum` is intentional here: the core event loop owns the subscription
// lifecycle, while target-specific files extend the operation set with the
// cases they can lower. That keeps fs/io/network/process/timer code talking in
// semantic requests instead of raw poll, IOCP, or thread-pool details.
//
// Add new variants close to the backend that implements them. Prefer helper
// constructors such as `OperationSpec::read` so call sites do not depend on
// constructor layout.
priv extenum OperationSpec {}

///|
// Backend-owned operation handle stored by subscriptions for wakeup,
// cancellation, and result extraction. Its variants are also extended by the
// backend that knows how to interpret them.
//
// A completed operation is returned to the caller and must be freed by the
// caller after extracting backend-specific results. A cancelled or failed
// operation is freed by `perform_operation`.
priv extenum SubmittedOperation {}

///|
// WASIp1 currently uses callback timers only; native operation waits construct
// `Wake`.
#warnings("-unused_constructor")
priv enum WaitHandler {
  Wake(@coroutine.Coroutine)
  Callback(() -> Unit)
}

///|
fn WaitHandler::wake(self : WaitHandler) -> Unit {
  match self {
    Wake(coro) => coro.wake()
    Callback(callback) => callback()
  }
}

///|
fn WaitHandler::cancel(self : WaitHandler) -> Unit {
  match self {
    Wake(coro) => coro.cancel()
    Callback(_) => ()
  }
}

///|
priv struct Subscription {
  operation : SubmittedOperation
  handler : WaitHandler
}

///|
let curr_loop : Ref[EventLoop?] = Ref(None)

///|
fn EventLoop::destroy(evloop : EventLoop) -> Unit {
  evloop.backend.destroy(evloop)
}

///|
pub fn with_event_loop(f : async () -> Unit) -> Unit raise {
  guard curr_loop.val is None
  let evloop = {
    subscription_id: 0,
    subscriptions: {},
    backend: Backend::new(),
  }
  defer evloop.destroy()
  curr_loop.val = Some(evloop)
  defer {
    curr_loop.val = None
  }
  let main = evloop.backend.spawn_main(evloop, f)
  evloop.run_forever()
  main.unwrap()
}

///|
fn EventLoop::next_subscription_id(self : EventLoop) -> Int {
  self.subscription_id += 1
  self.subscription_id
}

///|
fn EventLoop::store_subscription(
  self : EventLoop,
  subscription_id : Int,
  operation : SubmittedOperation,
  handler : WaitHandler,
) -> Unit {
  self.subscriptions[subscription_id] = { operation, handler }
}

///|
fn EventLoop::subscribe_operation(
  self : EventLoop,
  spec : OperationSpec,
  handler : WaitHandler,
) -> (Int, SubmittedOperation) {
  self.subscribe_backend_operation(
    subscription_id => self.backend.submit_operation(subscription_id, spec),
    handler,
  )
}

///|
fn EventLoop::subscribe_backend_operation(
  self : EventLoop,
  submit : (Int) -> SubmittedOperation,
  handler : WaitHandler,
) -> (Int, SubmittedOperation) {
  let subscription_id = self.next_subscription_id()
  let operation = submit(subscription_id)
  self.store_subscription(subscription_id, operation, handler)
  (subscription_id, operation)
}

///|
fn EventLoop::unsubscribe(self : EventLoop, subscription_id : Int) -> Unit {
  guard self.subscriptions.get(subscription_id) is Some(subscription) else {  }
  self.subscriptions.remove(subscription_id)
  self.backend.operation_cancelled(subscription.operation)
}

///|
fn EventLoop::deliver(self : EventLoop, subscription_id : Int) -> Unit {
  guard self.subscriptions.get(subscription_id) is Some(subscription) else {  }
  self.subscriptions.remove(subscription_id)
  self.backend.operation_cancelled(subscription.operation)
  subscription.handler.wake()
}

///|
fn EventLoop::deliver_all(self : EventLoop, ready : Array[Int]) -> Unit {
  for subscription_id in ready {
    self.deliver(subscription_id)
  }
}

///|
fn EventLoop::cleanup_subscriptions(self : Self) -> Unit {
  for _, subscription in self.subscriptions {
    self.backend.operation_cancelled(subscription.operation)
    subscription.handler.cancel()
  }
  self.subscriptions.clear()
}

///|
fn EventLoop::has_pending_work(self : Self) -> Bool {
  !@coroutine.no_more_work() || self.backend.has_pending_work()
}

///|
fn EventLoop::run_forever(self : Self) -> Unit raise {
  try {
    while self.has_pending_work() {
      let ready = self.backend.poll(
        self,
        blocking=!@coroutine.has_immediately_ready_task(),
      ) catch {
        @os_error.OSError(_) as err if err.is_EINTR() => continue
        err => raise err
      }
      self.deliver_all(ready)
      @coroutine.reschedule()
    }
  } catch {
    err => {
      Ref::protect(check_fd_leak, false, () => self.cleanup_after_error())
      // Propagate fatal loop errors to suspended coroutines before re-raising.
      while !@coroutine.no_more_work() {
        @coroutine.reschedule()
      }
      raise err
    }
  } noraise {
    _ => self.cleanup_after_success()
  }
}

///|
struct Timer(Int)

///|
pub fn Timer::new(duration : Int, callback : () -> Unit) -> Timer {
  guard curr_loop.val is Some(evloop)
  let deadline = if duration <= 0 {
    @time.ms_since_epoch()
  } else {
    @time.ms_since_epoch() + duration.to_int64()
  }
  let (subscription_id, _) = evloop.subscribe_operation(
    OperationSpec::timer(deadline),
    Callback(callback),
  )
  Timer(subscription_id)
}

///|
pub fn Timer::cancel(timer : Timer) -> Unit {
  guard curr_loop.val is Some(evloop)
  let Timer(subscription_id) = timer
  evloop.unsubscribe(subscription_id)
}
