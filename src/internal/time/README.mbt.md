# Time Utilities

This package provides internal time utilities for the MoonBit async library.

## Overview

The `time` package contains low-level time functions used internally by the async runtime. It provides access to high-precision system time for timestamping, performance measurement, and time-based operations.

## Functions

### `ms_since_epoch`

Returns the current time as milliseconds elapsed since the Unix epoch (January 1, 1970 UTC).

```moonbit
test "ms_since_epoch returns positive timestamp" {
  let timestamp = @time.ms_since_epoch()
  assert_true(timestamp > 0L)
}

test "ms_since_epoch is monotonic" {
  let start = @time.ms_since_epoch()
  let end = @time.ms_since_epoch()
  assert_true(end >= start)
}
```

**Use Cases:**
- Timestamping events in async operations
- Performance measurement and profiling
- Time-based calculations in schedulers
- Timeout implementations
- Rate limiting and throttling

**Note:** This is an internal utility function. External users should use the higher-level time APIs provided by the main async library.

## Implementation Details

The function is implemented as a C foreign function interface (FFI) that calls the system's `gettimeofday()` function on Unix-like systems. This provides microsecond precision, which is then converted to milliseconds for the return value.

## Thread Safety

The `ms_since_epoch` function is thread-safe and can be called from multiple concurrent contexts without synchronization.
