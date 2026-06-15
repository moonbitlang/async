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
async test "subscription delivery targets matching source" {
  guard curr_loop.val is Some(evloop)
  let log : Array[Int] = []
  let (read_id, _) = evloop.subscribe_operation(
    OperationSpec::fd_read(@fd_util.invalid_fd),
    Callback(() => log.push(1)),
  )
  let (write_id, _) = evloop.subscribe_operation(
    OperationSpec::fd_write(@fd_util.invalid_fd),
    Callback(() => log.push(2)),
  )
  evloop.deliver(write_id)
  assert_true(log == [2])
  assert_true(evloop.subscriptions.get(read_id) is Some(_))
  assert_false(evloop.subscriptions.get(write_id) is Some(_))
  evloop.deliver(read_id)
  assert_true(log == [2, 1])
  assert_false(evloop.subscriptions.get(read_id) is Some(_))
}

///|
#cfg(not(platform="windows"))
async test "fd operation uses common subscription" {
  guard curr_loop.val is Some(evloop)
  @async.with_task_group() <| group => {
    let task = group.spawn(() => {
      wait_operation(OperationSpec::fd_read(@fd_util.invalid_fd))
    })
    @async.pause()
    let subscription_id = evloop.subscription_id
    assert_true(evloop.subscriptions.get(subscription_id) is Some(_))
    evloop.deliver(subscription_id)
    task.wait()
  }
}

///|
#cfg(not(platform="windows"))
async test "unsubscribe removes common subscription" {
  guard curr_loop.val is Some(evloop)
  let (subscription_id, _) = evloop.subscribe_operation(
    OperationSpec::fd_read(@fd_util.invalid_fd),
    Callback(() => ()),
  )
  assert_true(evloop.subscriptions.get(subscription_id) is Some(_))
  evloop.unsubscribe(subscription_id)
  assert_false(evloop.subscriptions.get(subscription_id) is Some(_))
}
