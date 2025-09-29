cmake_minimum_required(VERSION 3.10)

project(wasix-cat)

set(CMAKE_SYSROOT "$ENV{WASIX_SYSROOT}")
set(CMAKE_TOOLCHAIN_FILE "${CMAKE_SOURCE_DIR}/clang-wasix.cmake_toolchain")

# Include MoonBit library
set(MOON_HOME "$ENV{MOON_HOME}")
add_library(moonbit STATIC "${MOON_HOME}/lib/runtime.c")
include_directories(moonbit PUBLIC "${MOON_HOME}/include")

# Add executable
add_executable(wasix-cat.wasm ./target/native/release/build/cat/cat.c)
target_sources(wasix-cat.wasm PRIVATE
    ${CMAKE_SOURCE_DIR}/../src/fs/stub.c
    ${CMAKE_SOURCE_DIR}/../src/internal/c_buffer/stub.c
    ${CMAKE_SOURCE_DIR}/../src/internal/event_loop/misc_stub.c
    ${CMAKE_SOURCE_DIR}/../src/internal/event_loop/poll.c
    ${CMAKE_SOURCE_DIR}/../src/internal/event_loop/thread_pool.c
    ${CMAKE_SOURCE_DIR}/../src/internal/fd_util/stub.c
    ${CMAKE_SOURCE_DIR}/../src/internal/time/time.c
    ${CMAKE_SOURCE_DIR}/../src/os_error/stub.c
    ${CMAKE_SOURCE_DIR}/../src/pipe/stub.c
    ${CMAKE_SOURCE_DIR}/../src/process/stub.c
    ${CMAKE_SOURCE_DIR}/../src/socket/socket.c
    ${CMAKE_SOURCE_DIR}/../src/tls/stub.c
)
target_link_libraries(wasix-cat.wasm PRIVATE moonbit)
