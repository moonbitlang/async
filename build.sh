#!/bin/bash
/Users/yezihang/Documents/wasi-sdk/bin/clang -c \
    --sysroot=$WASIX_SYSROOT/sysroot \
    -D_WASI_EMULATED_PROCESS_CLOCKS -lwasi-emulated-process-clocks \
    -D_WASI_EMULATED_SIGNAL \
    -D__linux__ \
    -pthread \
    -I ~/.moon/include \
    ~/.moon/lib/runtime.c \
    src/internal/event_loop/poll.c \
    src/internal/event_loop/misc_stub.c \
    src/internal/event_loop/thread_pool.c \
    src/fs/stub.c \
    src/internal/c_buffer/stub.c \
    src/internal/fd_util/stub.c \
    src/internal/time/time.c \
    src/os_error/stub.c \
    src/pipe/stub.c \
    src/process/stub.c \
    src/socket/socket.c \
    src/tls/stub.c \
    examples/target/native/release/build/cat/cat.c \
    