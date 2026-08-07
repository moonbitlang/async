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

#include <stdint.h>
#include <stdlib.h>
#include <moonbit.h>

#ifdef _WIN32

#include <windows.h>

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

#ifdef __MACH__
#include <sys/event.h>
#endif

typedef void* thread_worker_result_t;
#define THREAD_PROC_CALLING_CONVENTION

typedef int HANDLE;

#endif

#ifdef _WIN32

struct {
  HANDLE async_event;
  HANDLE main_event;
} main_loop = { INVALID_HANDLE_VALUE, INVALID_HANDLE_VALUE };

#else

struct {
  int pipe_r, pipe_w;
} main_loop = { -1, -1 };

#endif

MOONBIT_FFI_EXPORT
int32_t init_main_loop(void) {
#ifdef _WIN32

  main_loop.async_event = CreateEventA(NULL, FALSE, FALSE, NULL);
  main_loop.main_event = CreateEventA(NULL, FALSE, FALSE, NULL);
  return 0;

#else

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

#endif
}

MOONBIT_FFI_EXPORT
void destroy_main_loop() {
#ifdef _WIN32

  CloseHandle(main_loop.async_event);
  CloseHandle(main_loop.main_event);

#else

  if (main_loop.pipe_r >= 0)
    close(main_loop.pipe_r);

  if (main_loop.pipe_w >= 0)
    close(main_loop.pipe_w);

#endif
}

MOONBIT_FFI_EXPORT
void wakeup_main_loop() {
#ifdef _WIN32

  SetEvent(main_loop.async_event);

#else

  int32_t data = 1;
  write(main_loop.pipe_w, &data, sizeof(data));

#endif
}

MOONBIT_FFI_EXPORT
int32_t wait_main_loop(int32_t timeout) {
#ifdef _WIN32

  HANDLE const handles[] = { main_loop.async_event, main_loop.main_event };
  DWORD ret = WaitForMultipleObjects(2, handles, FALSE, timeout < 0 ? INFINITE : timeout);

  if (ret == WAIT_FAILED)
    return -1;

  if (ret == WAIT_TIMEOUT)
    return 0;

  return ret - WAIT_OBJECT_0 + 1;

#else

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

#endif
}

struct TriggerEventWorker {
  HANDLE pipe_w; // invalid => wake up main loop
  int32_t data;
  int32_t delay;
};

static
thread_worker_result_t THREAD_PROC_CALLING_CONVENTION main_loop_event_worker(void *payload) {
  struct TriggerEventWorker *request = (struct TriggerEventWorker*)payload;

#ifdef _WIN32

  Sleep(request->delay);

  if (request->pipe_w == INVALID_HANDLE_VALUE) {
    SetEvent(main_loop.main_event);
  } else {
    DWORD n_written;
    WriteFile(request->pipe_w, &request->data, sizeof(request->data), &n_written, NULL);
  }

#else

  struct timespec duration = { request->delay / 1000, (request->delay % 1000) * 1000000 };

#ifdef __MACH__
  // On GitHub CI MacOS runner, `nanosleep` is very imprecise,
  // causing corrupted test result.
  // However `kqueue` seems to have very accurate timing.
  int kqfd = kqueue();
  struct kevent kev;
  kevent(kqfd, 0, 0, &kev, 1, &duration);
  close(kqfd);
#else
  nanosleep(&duration, 0);
#endif

  if (request->pipe_w < 0) {
    int32_t data = 2;
    write(main_loop.pipe_w, &data, sizeof(data));
  } else {
    write(request->pipe_w, &request->data, sizeof(request->data));
  }

#endif

  free(payload);
  return 0;
}

MOONBIT_FFI_EXPORT
void trigger_event(HANDLE pipe_w, int32_t data, int32_t delay) {
  struct TriggerEventWorker *request =
    (struct TriggerEventWorker*)malloc(sizeof(struct TriggerEventWorker));

  request->pipe_w = pipe_w;
  request->data = data;
  request->delay = delay;

#ifdef _WIN32

  CreateThread(NULL, 512, &main_loop_event_worker, request, 0, 0);

#else

  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 512);

  pthread_t tid;
  pthread_create(&tid, &attr, &main_loop_event_worker, request);
  pthread_attr_destroy(&attr);

#endif
}

#ifndef _WIN32

struct PipeBurstWriter {
  int pipe_w;
  int32_t burst_count;
  int32_t burst_size;
  int32_t gap_us;
};

static thread_worker_result_t THREAD_PROC_CALLING_CONVENTION
pipe_burst_writer_main(void *payload) {
  struct PipeBurstWriter *writer = (struct PipeBurstWriter *)payload;
  char *buffer = (char *)calloc((size_t)writer->burst_size, 1);

  if (buffer != NULL) {
    for (int32_t burst = 0; burst < writer->burst_count; ++burst) {
      int32_t offset = 0;
      while (offset < writer->burst_size) {
        ssize_t written = write(
          writer->pipe_w,
          buffer + offset,
          (size_t)(writer->burst_size - offset)
        );
        if (written > 0) {
          offset += (int32_t)written;
          continue;
        }
        if (written < 0 && errno == EINTR)
          continue;
        if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
          struct pollfd pfd = { writer->pipe_w, POLL_OUT, 0 };
          if (poll(&pfd, 1, -1) >= 0)
            continue;
        }
        goto done;
      }

      if (writer->gap_us > 0) {
        struct timespec gap = {
          writer->gap_us / 1000000,
          (writer->gap_us % 1000000) * 1000,
        };
        while (nanosleep(&gap, &gap) < 0 && errno == EINTR) {}
      }
    }
  }

done:
  free(buffer);
  close(writer->pipe_w);
  free(writer);
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_external_loop_test_start_pipe_burst_writer(
  int pipe_w,
  int32_t burst_count,
  int32_t burst_size,
  int32_t gap_us
) {
  struct PipeBurstWriter *writer =
    (struct PipeBurstWriter *)malloc(sizeof(struct PipeBurstWriter));
  if (writer == NULL)
    return -1;

  writer->pipe_w = dup(pipe_w);
  writer->burst_count = burst_count;
  writer->burst_size = burst_size;
  writer->gap_us = gap_us;
  if (writer->pipe_w < 0) {
    free(writer);
    return -1;
  }

  pthread_t tid;
  int ret = pthread_create(&tid, NULL, &pipe_burst_writer_main, writer);
  if (ret != 0) {
    close(writer->pipe_w);
    free(writer);
    errno = ret;
    return -1;
  }
  pthread_detach(tid);
  return 0;
}

#endif
