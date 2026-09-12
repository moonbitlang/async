///|
test "IO pause preserves round robin scheduling" {
  let log : Array[Int] = []
  let a = spawn(() => {
    for _ in 0..<3 {
      log.push(1)
      pause_after_io()
    }
  })
  let b = spawn(() => {
    for _ in 0..<3 {
      log.push(2)
      pause_after_io()
    }
  })
  while has_immediately_ready_task() {
    reschedule()
  }
  guard! a.unwrap() is Continue
  guard! b.unwrap() is Continue
  assert_eq(log, [1, 2, 1, 2, 1, 2])
}

///|
test "IO pause delivers completed IO then preserves cancellation" {
  let log : Array[String] = []
  let a = spawn(() => {
    log.push("started")
    pause_after_io()
    log.push("delivered")
    assert_false(current_coroutine().shielded)
    check_cancellation()
    log.push("unreachable")
  })
  a.cancel()
  while has_immediately_ready_task() {
    reschedule()
  }
  guard! a.unwrap() is Cancelled
  assert_eq(log, ["started", "delivered"])
}

///|
test "IO pause restores an enclosing cancellation shield" {
  let log : Array[String] = []
  let a = spawn(() => {
    protect_from_cancel(() => {
      current_coroutine().cancel()
      pause_after_io()
      assert_true(current_coroutine().shielded)
      assert_true(current_coroutine().cancelled)
      log.push("delivered")
    })
    assert_false(current_coroutine().shielded)
    check_cancellation()
    log.push("unreachable")
  })
  while has_immediately_ready_task() {
    reschedule()
  }
  guard! a.unwrap() is Cancelled
  assert_eq(log, ["delivered"])
}

///|
test "IO pause delivers completed IO when cancelled during suspension" {
  let log : Array[String] = []
  let a = spawn(() => {
    log.push("started")
    pause_after_io()
    log.push("delivered")
    check_cancellation()
    log.push("unreachable")
  })
  let b = spawn(() => {
    assert_eq(log, ["started"])
    a.cancel()
  })
  while has_immediately_ready_task() {
    reschedule()
  }
  guard! a.unwrap() is Cancelled
  guard! b.unwrap() is Continue
  assert_eq(log, ["started", "delivered"])
}
