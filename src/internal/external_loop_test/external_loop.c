/*
 * Copyright 2025 International Digital Economy Academy
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <asm-generic/errno.h>
#include <stdint.h>
#include <moonbit.h>

#ifdef _WIN32

typedef DWORD thread_worker_result_t;
#define THREAD_PROC_CALLING_CONVENTION WINAPI

// #ifdef _WIN32
#else

#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/wait.h>
#include <pthread.h>

typedef void* thread_worker_result_t;
#define THREAD_PROC_CALLING_CONVENTION

#endif

struct {
  int pipe_r, pipe_w;
} main_loop = { -1, -1 };

MOONBIT_FFI_EXPORT
int32_t init_main_loop(void) {
  int fds[2];
  if (pipe(fds) < 0)
    return -1;

  main_loop.pipe_r = fds[0];
  main_loop.pipe_w = fds[1];

  int flags = fcntl(main_loop.pipe_r, F_GETFL);
  if (flags < 0) return -1;

  if (!(flags & O_NONBLOCK) && fcntl(main_loop.pipe_r, F_SETFL, flags | O_NONBLOCK) < 0)
    return -1;

  return 0;
}

MOONBIT_FFI_EXPORT
void destroy_main_loop() {
  if (main_loop.pipe_r >= 0)
    close(main_loop.pipe_r);

  if (main_loop.pipe_w >= 0)
    close(main_loop.pipe_w);
}

MOONBIT_FFI_EXPORT
void wakeup_main_loop() {
  int32_t data = 1;
  write(main_loop.pipe_w, &data, sizeof(data));
}

MOONBIT_FFI_EXPORT
int32_t wait_main_loop(int32_t timeout) {
  int msg;
  int ret = read(main_loop.pipe_r, &msg, sizeof(msg));
  if (ret > 0)
    return msg;

  if (ret == 0)
    return 0;

  if (errno != EAGAIN && errno != EWOULDBLOCK) {
    return -1;
  }

  if (timeout == 0)
    return 0;

  struct pollfd pfd = { main_loop.pipe_r, POLL_IN, 0 };
  if (poll(&pfd, 1, timeout) < 0)
    return -1;

  if (!(pfd.revents & POLL_IN))
    return 0;

  ret = read(main_loop.pipe_r, &msg, sizeof(msg));
  return ret > 0 ? msg : ret;
}

static
thread_worker_result_t THREAD_PROC_CALLING_CONVENTION main_loop_event_worker(void *payload) {
  uintptr_t delay = (uintptr_t)payload;

  struct timespec duration = { delay / 1000, (delay % 1000) * 1000000 };
  nanosleep(&duration, 0);

  int32_t data = 2;
  write(main_loop.pipe_w, &data, sizeof(data));
  return 0;
}

MOONBIT_FFI_EXPORT
void trigger_main_loop_event(int32_t delay) {
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 512);

  pthread_t tid;
  pthread_create(&tid, &attr, &main_loop_event_worker, (void*)(uintptr_t)delay);
  pthread_attr_destroy(&attr);
}
