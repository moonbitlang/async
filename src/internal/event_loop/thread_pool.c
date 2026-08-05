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
#include <moonbit.h>

#ifdef _WIN32

#ifndef _MSC_VER
#error "Currently only MSVC is supported on Windows"
#endif

#include <winsock2.h>
#include <windows.h>
#include <ws2tcpip.h>
#include <stddef.h>

#else

#include <pthread.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#if !defined(__ANDROID__) || __ANDROID_API__ >= 28
#include <spawn.h>
#endif
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/wait.h>
#include <poll.h>

#ifdef __linux__
#include <sys/syscall.h>
#include <sys/inotify.h>
#include <linux/version.h>
#endif

#ifdef __MACH__
#include <sys/attr.h>
#endif

typedef int HANDLE;
typedef int SOCKET;
#define GetLastError() errno
#define SetLastError(err) errno = err

#endif


#ifdef _WIN32
// Windows, use native event system to wake up worker thread
#define WAKEUP_METHOD_EVENT

#elif defined(__MACH__)
// MacOS, there are some bug with thread-directed signal and `sigwait`,
// so use condition variable to wake up worker threads
#include <sys/event.h>
#define WAKEUP_METHOD_COND_VAR

#include <Availability.h>
#ifdef __MAC_OS_X_VERSION_MIN_REQUIRED
#if __MAC_OS_X_VERSION_MIN_REQUIRED >= 260000
#define posix_spawn_file_actions_addchdir_np posix_spawn_file_actions_addchdir
#endif
#endif

#else
// Other UNIX-like systems, use signal and `sigwait` to wake up worker threads
#define WAKEUP_METHOD_SIGNAL

#if defined(__ANDROID__) && __ANDROID_API__ < 34
#define posix_spawn_file_actions_addchdir_np(...) ENOSYS
#endif

#endif

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_get_platform() {
#ifdef __linux__
  return 0;
#elif defined(__MACH__)
  return 1;
#elif defined(_WIN32)
  return 2;
#else
  abort();
#endif
}

struct job {
  // the return value of the job.
  // should be set by the worker and read by waiter.
  // for result that cannot fit in an integer,
  // jobs can also store extra result in their payload
  int32_t ret;

  // the error code of the job.
  // should be zefo iff the job succeeds
  int32_t err;

  // The worker that actually performs the job.
  // it will receive the payload of the job as parameter.
  // The return value of `worker` will become the return status of the whole job.
  // In case of failure, `worker` should write error number to the second parameter.
  int32_t (*worker)(void *, int32_t *);

  // finalizer for the job
  void (*free)(void *);

  // Special cancellation function for the job.
  // May be `NULL`, in this case the default one is used.
  // Receive the payload of the job as parameter.
  int32_t (*cancel_handler)(void *);

  // Extra payload of the specific job,
  // Directly inlined into `struct job` to avoid indirection.
  char payload[];
};

// We pass jobs by payload pointer for convenience,
// the `JOB_HEADER` macro extracts the header pointer when necessary.
#define JOB_HEADER(payload_ptr) ((struct job*)(payload_ptr) - 1)

MOONBIT_FFI_EXPORT
void moonbitlang_async_free_job(void *payload_ptr) {
  struct job *job = JOB_HEADER(payload_ptr);
  (job->free)(job->payload);
  free(job);
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_job_get_ret(void *job) {
  return JOB_HEADER(job)->ret;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_job_get_err(void *job) {
  return JOB_HEADER(job)->err;
}

// =======================================================
// =================== the thread pool ===================
// =======================================================

struct {
  int initialized;

  HANDLE notify_send;
  HANDLE notify_recv;

#ifndef _WIN32
  sigset_t worker_sigmask;
  sigset_t old_sigmask;
#endif
#ifdef WAKEUP_METHOD_SIGNAL
  sigset_t wakeup_signal;
#endif
} pool;

// The type for a worker thread
struct worker {
#ifdef _WIN32
  HANDLE id;
#else
  pthread_t id;
#endif

  // an unique identifier for current job,
  // used to find the waiter of a job
  int32_t job_id;

  // the job currently being processed
  struct job *job;

  int waiting;

#ifdef WAKEUP_METHOD_EVENT
  HANDLE event;
#elif defined(WAKEUP_METHOD_COND_VAR)
  pthread_mutex_t mutex;
  pthread_cond_t cond;
#endif
};

#ifdef _WIN32

typedef DWORD thread_worker_result_t;
#define THREAD_PROC_CALLING_CONVENTION WINAPI

#else

typedef void* thread_worker_result_t;
#define THREAD_PROC_CALLING_CONVENTION

#endif

static
thread_worker_result_t THREAD_PROC_CALLING_CONVENTION worker_loop(void *data) {
  int sig;
  struct worker *self = (struct worker*)data;

  int job_id = self->job_id;
  struct job *job = self->job;

#ifdef WAKEUP_METHOD_EVENT
  self->event = CreateEventA(NULL, FALSE, FALSE, NULL);
#elif defined(WAKEUP_METHOD_COND_VAR)
  pthread_mutex_init(&(self->mutex), 0);
  pthread_cond_init(&(self->cond), 0);
#endif

  while (job) {
    job->err = 0;
    job->ret = job->worker(job->payload, &job->err);

    self->waiting = 1;

#ifdef _WIN32
    PostQueuedCompletionStatus(
      pool.notify_send,
      job_id,
      (ULONG_PTR)pool.notify_recv,
      0
    );
#else
    do {
      if (write(pool.notify_send, &job_id, sizeof(int)) > 0)
        break;
    } while (errno == EINTR);
#endif

#ifdef WAKEUP_METHOD_EVENT
    WaitForSingleObject(self->event, INFINITE);
#elif defined(WAKEUP_METHOD_SIGNAL)
    sigwait(&pool.wakeup_signal, &sig);
#elif defined(WAKEUP_METHOD_COND_VAR)
    pthread_mutex_lock(&(self->mutex));
    while (self->waiting) {
#ifdef __MACH__
      // There's a bug in the MacOS's `pthread_cond_wait`,
      // see https://github.com/graphia-app/graphia/issues/33
      // We know the arguments must be valid here, so use a loop to work around
      while (pthread_cond_wait(&(self->cond), &(self->mutex)) == EINVAL) {}
#else
      pthread_cond_wait(&(self->cond), &(self->mutex));
#endif
    }
    pthread_mutex_unlock(&(self->mutex));
#endif
    job_id = self->job_id;
    job = self->job;
  }
  return 0;
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_wake_worker(
  struct worker *worker,
  int32_t job_id,
  void *job
) {
  worker->job_id = job_id;
  worker->job = job ? JOB_HEADER(job) : 0;

#ifdef WAKEUP_METHOD_EVENT
  worker->waiting = 0;
  SetEvent(worker->event);
#elif defined(WAKEUP_METHOD_SIGNAL)
  worker->waiting = 0;
  pthread_kill(worker->id, SIGUSR1);
#elif defined(WAKEUP_METHOD_COND_VAR)
  pthread_mutex_lock(&(worker->mutex));
  worker->waiting = 0;
  pthread_cond_signal(&(worker->cond));
  pthread_mutex_unlock(&(worker->mutex));
#endif
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_worker_enter_idle(struct worker *worker) {
  worker->job = 0;
}

enum {
  CANCELLATION_STATUS_RETRY_LATER = 0,
  CANCELLATION_STATUS_NEED_WAIT = 1,
};

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_cancel_worker(struct worker *worker) {
  if (worker->waiting)
    return 1;

  // invarint: `worker->job` is only manipulated in the main thread,
  // and must be non-NULL here.
  if (worker->job->cancel_handler)
    return (worker->job->cancel_handler)(worker->job->payload);

  // enter default cancellation logic

#ifdef _WIN32

  if (CancelSynchronousIo(worker->id)) {
    return CANCELLATION_STATUS_NEED_WAIT;
  } else if (GetLastError() == ERROR_NOT_FOUND) {
    return CANCELLATION_STATUS_RETRY_LATER;
  } else {
    return -1;
  }

#else

  pthread_kill(worker->id, SIGUSR2);
  return CANCELLATION_STATUS_RETRY_LATER;

#endif
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_free_worker(struct worker *worker) {
  // terminate the worker
  moonbitlang_async_wake_worker(worker, 0, 0);

#ifdef _WIN32
  WaitForSingleObject(worker->id, INFINITE);
#else
  pthread_join(worker->id, 0);
#endif

#ifdef WAKEUP_METHOD_EVENT
  CloseHandle(worker->event);
#elif defined(WAKEUP_METHOD_COND_VAR)
  pthread_mutex_destroy(&(worker->mutex));
  pthread_cond_destroy(&(worker->cond));
#endif

  free(worker);
}

#ifndef _WIN32
static
void nop_signal_handler(int signum) {}

int moonbitlang_async_event_bus_register(int event_bus, int fd, int32_t read_only);
#endif

MOONBIT_FFI_EXPORT
HANDLE moonbitlang_async_init_thread_pool(HANDLE event_bus) {
  if (pool.initialized)
    abort();

#ifndef _WIN32
  sigfillset(&pool.worker_sigmask); 
  // used for cancelling blocking IO in worker thread
  sigdelset(&pool.worker_sigmask, SIGUSR2);

  sigset_t signals_to_block;
  sigemptyset(&signals_to_block);
  sigaddset(&signals_to_block, SIGCHLD);

#ifdef WAKEUP_METHOD_SIGNAL
  sigemptyset(&pool.wakeup_signal);
  sigaddset(&pool.wakeup_signal, SIGUSR1);
  sigaddset(&signals_to_block, SIGUSR1);
#endif

  pthread_sigmask(SIG_BLOCK, &signals_to_block, &pool.old_sigmask);

  signal(SIGPIPE, SIG_IGN);

  // register a dummy handler for `SIGUSR2,
  // so that when we cancel blocking IO in worker thread via `SIGUSR2`:
  // 1. the program won't get killed
  // 2. blocked syscall will be interrupted
  struct sigaction act;
  act.sa_handler = nop_signal_handler;
  sigemptyset(&act.sa_mask);
  act.sa_flags = 0;
  sigaction(SIGUSR2, &act, NULL);
#endif

#ifdef _WIN32

  // On Windows, job completion is sent through IOCP directly
  pool.notify_send = event_bus;

  // We never receive completion notification for the IOCP port itself.
  // So we can safely use the IOCP port as the handle in
  // custom completion packet to indicate this come from the thread pool.
  pool.notify_recv = event_bus;

#else

  int notify_pipe[2];
  if (pipe(notify_pipe) < 0)
    return -1;

  for (int i = 0; i < 2; ++i) {
    int fd = notify_pipe[i];
    int flags = fcntl(fd, F_GETFD);
    if (flags < 0)
      goto cleanup_with_pipe;

    if (!(flags & FD_CLOEXEC))
      if (fcntl(fd, F_SETFD, flags | FD_CLOEXEC) < 0)
        goto cleanup_with_pipe;
  }

  pool.notify_recv = notify_pipe[0];
  pool.notify_send = notify_pipe[1];

  if (moonbitlang_async_event_bus_register(event_bus, pool.notify_recv, 1) < 0)
    goto cleanup_with_pipe;

#endif

  pool.initialized = 1;
  return pool.notify_recv;

#ifndef _WIN32
cleanup_with_pipe:
  close(notify_pipe[0]);
  close(notify_pipe[1]);
  return -1;
#endif
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_destroy_thread_pool() {
  if (!pool.initialized)
    abort();

  pool.initialized = 0;

#ifndef _WIN32
  pthread_sigmask(SIG_SETMASK, &pool.old_sigmask, 0);
  close(pool.notify_recv);
  close(pool.notify_send);
#endif
}

MOONBIT_FFI_EXPORT
struct worker *moonbitlang_async_spawn_worker(
  int32_t init_job_id,
  void *init_job
) {
  struct worker *worker = (struct worker*)malloc(sizeof(struct worker));
  worker->job_id = init_job_id;
  worker->job = JOB_HEADER(init_job);
  worker->waiting = 0;

#ifdef _WIN32
  worker->id = CreateThread(
    NULL,
    512,
    &worker_loop,
    worker,
    0,
    0
  );
#else
  pthread_attr_t attr;
  pthread_attr_init(&attr);
#ifdef __ANDROID__
  pthread_attr_setstacksize(&attr, 64 * 1024);
#else
  pthread_attr_setstacksize(&attr, 512);
#endif

  // make sure the worker thread has correct sigmask immediately
  sigset_t curr_sigmask;
  pthread_sigmask(SIG_SETMASK, &pool.worker_sigmask, &curr_sigmask);

  pthread_create(&(worker->id), &attr, &worker_loop, worker);

  pthread_sigmask(SIG_SETMASK, &curr_sigmask, 0);

  pthread_attr_destroy(&attr);
#endif

  return worker;
}

#ifndef _WIN32
int32_t moonbitlang_async_fetch_completion(int notify_recv, int32_t *output) {
  int max_len = Moonbit_array_length(output);
  return read(notify_recv, (char*)output, max_len * sizeof(int32_t));
}
#endif

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_errno_is_cancelled(int32_t err) {
#ifdef _WIN32
  return err == ERROR_OPERATION_ABORTED;
#else
  return err == EINTR;
#endif
}

// =========================================================
// ===================== concrete jobs =====================
// =========================================================

MOONBIT_FFI_EXPORT
void *moonbitlang_async_make_job(
  int32_t size,
  void (*free)(void*),
  int32_t (*worker)(void*, int32_t*),
  int32_t (*cancel_handler)(void*)
) {
  struct job *job = (struct job*)malloc(size + sizeof(struct job));
  job->ret = 0;
  job->err = 0;
  job->worker = worker;
  job->free = free;
  job->cancel_handler = cancel_handler;
  return job->payload;
}

#define MAKE_JOB(name, cancel_handler) (struct name##_job*)moonbitlang_async_make_job(\
  sizeof(struct name##_job),\
  (void (*)(void*))free_##name##_job,\
  (int32_t (*)(void*, int32_t*)) name##_job_worker,\
  (int32_t (*)(void*))cancel_handler\
)

// ===== sleep job, sleep via thread pool, for testing only =====

struct sleep_job {
  int duration;
};

static
void free_sleep_job(struct sleep_job *job) {}

static
int32_t sleep_job_worker(struct sleep_job *job, int32_t *err_out) {
#ifdef _WIN32
  Sleep(job->duration);
#else
  int32_t ms = job->duration;
  struct timespec duration = { ms / 1000, (ms % 1000) * 1000000 };

#ifdef __MACH__
  // On GitHub CI MacOS runner, `nanosleep` is very imprecise,
  // causing corrupted test result.
  // However `kqueue` seems to have very accurate timing.
  // Since `OP_SLEEP` is only for testing purpose,
  // here we use `kqueue` (in an absolutely wrong way) to perform sleep.
  int kqfd = kqueue();
  struct kevent kev;
  kevent(kqfd, 0, 0, &kev, 1, &duration);
  close(kqfd);
#else
  nanosleep(&duration, 0);
#endif

#endif

  return 0;
}

MOONBIT_FFI_EXPORT
struct sleep_job *moonbitlang_async_make_sleep_job(int ms) {
  struct sleep_job *job = MAKE_JOB(sleep, 0);
  job->duration = ms;
  return job;
}

// ===== read job, for reading non-pollable stuff =====

struct read_job {
  HANDLE fd;
  char *buf;
  int offset;
  int len;
  int64_t position;
};

static
void free_read_job(struct read_job *job) {
  moonbit_decref(job->buf);
}

static
int32_t read_job_worker(struct read_job *job, int32_t *err_out) {
#ifdef _WIN32

   OVERLAPPED overlapped;
   memset(&overlapped, 0, sizeof(OVERLAPPED));
   if (job->position >= 0) {
     overlapped.Offset = job->position & 0xffffffff;
     overlapped.OffsetHigh = job->position >> 32;
   }

   DWORD bytes_transferred;
   BOOL result = ReadFile(
     job->fd,
     job->buf + job->offset,
     job->len,
     &bytes_transferred,
     job->position < 0 ? NULL : &overlapped
   );
   if (result) {
     return bytes_transferred;
   } else {
     int err = GetLastError();
     if (err == ERROR_HANDLE_EOF || err == ERROR_BROKEN_PIPE) {
       return 0;
     } else {
       *err_out = err;
       return -1;
     }
   }

#else

  int32_t ret;
  if (job->position < 0) {
    while (1) {
      ret = read(job->fd, job->buf + job->offset, job->len);
      if (ret >= 0)
        break;

      if (errno != EAGAIN && errno != EWOULDBLOCK)
        break;

      struct pollfd pfd = { job->fd, POLL_IN, 0 };
      if (poll(&pfd, 1, -1) < 0)
        break;
    }
  } else {
    ret = pread(
      job->fd,
      job->buf + job->offset,
      job->len,
      job->position
    );
  }

  if (ret < 0)
    *err_out = errno;

  return ret;

#endif
}

struct read_job *moonbitlang_async_make_read_job(
  HANDLE fd,
  char *buf,
  int offset,
  int len,
  int64_t position
) {
  struct read_job *job = MAKE_JOB(read, 0);
  job->fd = fd;
  job->buf = buf;
  job->offset = offset;
  job->len = len;
  job->position = position;
  return job;
}

// ===== write job, for writing non-pollable stuff =====

struct write_job {
  HANDLE fd;
  char *buf;
  int offset;
  int len;
  int64_t position;
};

static
void free_write_job(struct write_job *job) {
  moonbit_decref(job->buf);
}

static
int32_t write_job_worker(struct write_job *job, int32_t *err_out) {
#ifdef _WIN32

   OVERLAPPED overlapped;
   memset(&overlapped, 0, sizeof(OVERLAPPED));
   if (job->position >= 0) {
     overlapped.Offset = job->position & 0xffffffff;
     overlapped.OffsetHigh = job->position >> 32;
   }

   DWORD bytes_transferred;
   BOOL result = WriteFile(
     job->fd,
     job->buf + job->offset,
     job->len,
     &bytes_transferred,
     job->position < 0 ? NULL : &overlapped
   );
   if (result)
     return bytes_transferred;
   else {
     *err_out = GetLastError();
     return -1;
   }

#else

  int32_t ret;
  if (job->position < 0) {
    while (1) {
      ret = write(job->fd, job->buf + job->offset, job->len);
      if (ret >= 0)
        break;

      if (errno != EAGAIN && errno != EWOULDBLOCK)
        break;

      struct pollfd pfd = { job->fd, POLL_OUT, 0 };
      if (poll(&pfd, 1, -1) < 0)
        break;
    }
  } else {
    ret = pwrite(
      job->fd,
      job->buf + job->offset,
      job->len,
      job->position
    );
  }
  if (ret < 0)
    *err_out = errno;
  return ret;

#endif
}

struct write_job *moonbitlang_async_make_write_job(
  HANDLE fd,
  char *buf,
  int offset,
  int len,
  int64_t position
) {
  struct write_job *job = MAKE_JOB(write, 0);
  job->fd = fd;
  job->buf = buf;
  job->offset = offset;
  job->len = len;
  job->position = position;
  return job;
}

// ===== spawn job, spawn foreign process =====
#ifdef _WIN32

static
HANDLE global_job_object = INVALID_HANDLE_VALUE;

static
BOOL init_global_job_object() {
  HANDLE job = CreateJobObjectA(NULL, NULL);
  if (job == NULL)
    return 0;

  JOBOBJECT_EXTENDED_LIMIT_INFORMATION info;
  memset(&info, 0, sizeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));

  info.BasicLimitInformation.LimitFlags =
    JOB_OBJECT_LIMIT_BREAKAWAY_OK
    | JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK
    | JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

  if (
    !SetInformationJobObject(
      job,
      JobObjectExtendedLimitInformation,
      &info,
      sizeof(info)
    )
  ) {
    goto on_error;
  }

  if (!AssignProcessToJobObject(job, GetCurrentProcess())) {
    if (GetLastError() == ERROR_ACCESS_DENIED) {
      // Here we try to assign current process to the job for two purpose:
      //
      // 1. workaround the bug mentioned in https://github.com/libuv/libuv/pull/4152
      // 2. according to https://learn.microsoft.com/en-us/windows/win32/api/jobapi2/nf-jobapi2-assignprocesstojobobject,
      //    prior to Windows 8, a process can only be associated with a single job.
      //    In this case, if the main process is already in a job,
      //    our child process will by default also be in the same job,
      //    so we cannot associate child process to a new job.
      //    So here we simply give up auto-kill child process if
      //    we cannot assign current process to the new object, which means:
      //    
      //    a. we are in Windows 7 or earlier
      //    b. the main process is already associated with a job
      SetLastError(0);
    }
    goto on_error;
  }

  global_job_object = job;
  return 1;

on_error:
  CloseHandle(job);
  return 0;
}

struct spawn_job {
  LPWSTR command_line;
  void *environment;
  HANDLE stdio[3];
  LPWSTR cwd;
  int32_t no_console_window;
  int32_t is_orphan;
  int32_t init_error;
  HANDLE result;
};

static
void free_spawn_job(struct spawn_job *job) {
  moonbit_decref(job->command_line);
  free(job->environment);
  if (job->cwd)
    moonbit_decref(job->cwd);
  if (job->result != INVALID_HANDLE_VALUE)
    CloseHandle(job->result);
}

static
int32_t spawn_job_worker(struct spawn_job *job, int32_t *err_out) {
  static DWORD std_handle_values[] = {
    STD_INPUT_HANDLE,
    STD_OUTPUT_HANDLE,
    STD_ERROR_HANDLE
  };

  if (job->init_error) {
    // Handle error from initializing global job object,
    // see `moonbitlang_async_make_spawn_job` below.
    *err_out = job->init_error;
    return 0;
  }

  HANDLE handles_to_inherit[3];
  DWORD number_of_handles_to_inherit = 0;

  for (int i = 0; i < 3; ++i) {
    if (job->stdio[i] == INVALID_HANDLE_VALUE)
      job->stdio[i] = GetStdHandle(std_handle_values[i]);

    if (job->stdio[i] == INVALID_HANDLE_VALUE) {
      *err_out = GetLastError();
      return 0;
    }

    for (int j = 0; j < number_of_handles_to_inherit; ++j) {
      if (handles_to_inherit[j] == job->stdio[i])
        goto handle_already_added;
    }

    handles_to_inherit[number_of_handles_to_inherit++] = job->stdio[i];

    if (
      !SetHandleInformation(
        job->stdio[i],
        HANDLE_FLAG_INHERIT,
        HANDLE_FLAG_INHERIT
      )
    ) {
      *err_out = GetLastError();
      return 0;
    }
  handle_already_added:
    ;
  }

  DWORD create_flags =
    CREATE_NEW_PROCESS_GROUP // so that we can gracefully terminate this process
                             // via sending Ctrl+Break console event
    | CREATE_UNICODE_ENVIRONMENT
    | EXTENDED_STARTUPINFO_PRESENT;

  if (job->no_console_window)
    create_flags |= CREATE_NO_WINDOW;

  STARTUPINFOEXW startup_info;
  memset(&startup_info, 0, sizeof(STARTUPINFOEXW));
  startup_info.StartupInfo.cb = sizeof(STARTUPINFOEXW);
  startup_info.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  startup_info.StartupInfo.hStdInput = job->stdio[0];
  startup_info.StartupInfo.hStdOutput = job->stdio[1];
  startup_info.StartupInfo.hStdError = job->stdio[2];

  SIZE_T attrs_size;
  InitializeProcThreadAttributeList(NULL, 2, 0, &attrs_size);
  startup_info.lpAttributeList = malloc(attrs_size);
  if (
    !InitializeProcThreadAttributeList(
      startup_info.lpAttributeList,
      2,
      0,
      &attrs_size
    )
  ) {
    *err_out = GetLastError();
    DeleteProcThreadAttributeList(startup_info.lpAttributeList);
    free(startup_info.lpAttributeList);
    return 0;
  }

  if (
    !UpdateProcThreadAttribute(
      startup_info.lpAttributeList,
      0, // reserved
      PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
      handles_to_inherit,
      number_of_handles_to_inherit * sizeof(HANDLE),
      NULL, // reserved
      NULL // reserved
    )
  ) {
    *err_out = GetLastError();
    DeleteProcThreadAttributeList(startup_info.lpAttributeList);
    free(startup_info.lpAttributeList);
    return 0;
  }

#ifdef PROC_THREAD_ATTRIBUTE_JOB_LIST

  if (!job->is_orphan) {
    // On Windows 10 and later, there is a way to
    // atomically assign a child process to new job atomically on creation.
    // This can avoid race condition when main process is killed after `CreateProcess`,
    // but before `AssignProcessToJobObject` on the child process.
    if (
      !UpdateProcThreadAttribute(
        startup_info.lpAttributeList,
        0,
        PROC_THREAD_ATTRIBUTE_JOB_LIST,
        &global_job_object,
        sizeof(global_job_object),
        NULL,
        NULL
      )
    ) {
      *err_out = GetLastError();
      DeleteProcThreadAttributeList(startup_info.lpAttributeList);
      free(startup_info.lpAttributeList);
      return 0;
    }
  }

#else

  // Notice that we are not setting `CREATE_BREAKAWAY_FROM_JOB` for orphan process here.
  // Because in case the main process is already in a job disallowing break away,
  // setting `CREATE_BREAKAWAY_FROM_JOB` will fail the `CreateProcess` call.
  if (!job->is_orphan && global_job_object != INVALID_HANDLE_VALUE) {
    // to avoid the child process exit too fast
    // before we assign it to the job object
    create_flags |= CREATE_SUSPENDED;
  }

#endif

  PROCESS_INFORMATION process_info;
  BOOL result = CreateProcessW(
    NULL,
    job->command_line,
    NULL, // security attributes for process
    NULL, // security attributes for main thread
    TRUE, // do not inherit handle
    create_flags,
    job->environment,
    job->cwd,
    (LPSTARTUPINFOW)&startup_info,
    &process_info
  );

  if (startup_info.lpAttributeList) {
    DeleteProcThreadAttributeList(startup_info.lpAttributeList);
    free(startup_info.lpAttributeList);
  }

  if (!result) {
    *err_out = GetLastError();
    return 0;
  }

  if (create_flags & CREATE_SUSPENDED) {
    // On Windows, hard termination is much more common,
    // due to lack of a universal way for graceful process termination.
    // So assign the new process to a job object,
    // so that it is automatically killed when the main process is killed.
    if (!AssignProcessToJobObject(global_job_object, process_info.hProcess)) {
      *err_out = GetLastError();
      TerminateProcess(process_info.hProcess, 1);
      return 0;
    }
    ResumeThread(process_info.hThread);
  }

  CloseHandle(process_info.hThread);
  job->result = process_info.hProcess;

  return process_info.dwProcessId;
}

struct spawn_job *moonbitlang_async_make_spawn_job(
  LPWSTR command_line,
  void *environment,
  HANDLE stdin_handle,
  HANDLE stdout_handle,
  HANDLE stderr_handle,
  int32_t is_orphan
) {
  struct spawn_job *job = MAKE_JOB(spawn, 0);
  job->command_line = command_line;
  job->environment = environment;
  job->stdio[0] = stdin_handle;
  job->stdio[1] = stdout_handle;
  job->stdio[2] = stderr_handle;
  job->cwd = NULL;
  job->no_console_window = FALSE;
  job->is_orphan = is_orphan;
  job->init_error = 0;
  job->result = INVALID_HANDLE_VALUE;

  if (global_job_object == INVALID_HANDLE_VALUE && !init_global_job_object())
    // To avoid race condition, we must initialize the global job object
    // in the main thread. However job spawning functions cannot report error,
    // so we delay the error reporting to the thread pool job
    job->init_error = errno;

  return job;
}

HANDLE moonbitlang_async_get_spawn_job_result_handle(struct spawn_job *job) {
  HANDLE result = job->result;
  job->result = INVALID_HANDLE_VALUE;
  return result;
}

void moonbitlang_async_spawn_job_set_cwd(struct spawn_job *job, LPWSTR cwd) {
  job->cwd = cwd;
}

void moonbitlang_async_spawn_job_set_no_console_window(struct spawn_job *job) {
  job->no_console_window = TRUE;
}

// For windows, waiting for process is done via one dedicated thread per process,
// As a future optimization, we may wait for multiple processes in a single thread.
// But that would make cancellation a lot trickier.

struct wait_for_process_job {
  HANDLE process;
  HANDLE cancel;
};

static
void free_wait_for_process_job(struct wait_for_process_job *job) {
  CloseHandle(job->cancel);
};

static
int32_t cancel_wait_for_process_job(struct wait_for_process_job *job) {
  SetEvent(job->cancel);
  return CANCELLATION_STATUS_NEED_WAIT;
}

static
int32_t wait_for_process_job_worker(struct wait_for_process_job *job, int32_t *err_out) {
  HANDLE handles[2] = { job->process, job->cancel };

  DWORD result = WaitForMultipleObjects(2, handles, FALSE, INFINITE);
  if (result == WAIT_FAILED)
    *err_out = GetLastError();
  else if (result == WAIT_OBJECT_0 + 1)
    *err_out = ERROR_OPERATION_ABORTED;
  return 0;
}

struct wait_for_process_job *moonbitlang_async_make_wait_for_process_job(
  HANDLE process,
  int32_t pid
) {
  struct wait_for_process_job *job = MAKE_JOB(wait_for_process, cancel_wait_for_process_job);
  job->process = process;
  job->cancel = CreateEventA(NULL, FALSE, FALSE, NULL);
  return job;
}

#else

struct spawn_job {
  char *path;
  char **args;
  char **envp;
  int stdio[3];
  char *cwd;
  int pidfd;
};

static
void free_spawn_job(struct spawn_job *job) {
  moonbit_decref(job->path);
  for (char **cursor = job->args; *cursor; ++cursor)
    free(*cursor);
  free(job->args);
  for (int i = 0; (job->envp)[i]; ++i) {
    free((job->envp)[i]);
  }
  free(job->envp);
  if (job->cwd)
    moonbit_decref(job->cwd);
  if (job->pidfd >= 0)
    close(job->pidfd);
}

#if defined(__ANDROID__) && __ANDROID_API__ < 28

// posix_spawn is unavailable on Android API < 28.
// Return a job pre-filled with ENOSYS so the caller gets a proper error
// instead of hanging forever (a NULL job causes the worker thread to exit
// without sending a completion notification).
static
int32_t spawn_job_worker(struct spawn_job *job, int32_t *err_out) {
  *err_out = ENOSYS;
  return 0;
}

#else // posix_spawn available

static
int32_t spawn_job_worker(struct spawn_job *job, int32_t *err_out) {
  posix_spawnattr_t attr;
  posix_spawnattr_init(&attr);
  posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);

  posix_spawnattr_setsigmask(&attr, &pool.old_sigmask);

  sigset_t all_signals;
  sigfillset(&all_signals);
  posix_spawnattr_setsigdefault(&attr, &all_signals);

  posix_spawn_file_actions_t file_actions;
  posix_spawn_file_actions_init(&file_actions);
  for (int i = 0; i < 3; ++i) {
    int fd = job->stdio[i];
    if (fd >= 0) {
      *err_out = posix_spawn_file_actions_adddup2(&file_actions, fd, i);
      if (*err_out) goto exit;
    }
  }
  if (job->cwd) {
    *err_out = posix_spawn_file_actions_addchdir_np(&file_actions, job->cwd);
    if (*err_out) goto exit;
  }

  int32_t ret = 0;
  if (strchr(job->path, '/')) {
    *err_out = posix_spawn(
      &ret,
      job->path,
      &file_actions,
      &attr,
      job->args,
      job->envp
    );
  } else {
    *err_out = posix_spawnp(
      &ret,
      job->path,
      &file_actions,
      &attr,
      job->args,
      job->envp
    );
  }

#ifdef __linux__
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 4, 0)
  if (!*err_out) {
    job->pidfd = syscall(SYS_pidfd_open, ret, 0);
    if (job->pidfd < 0 && errno != ENOSYS && errno != EPERM)
      *err_out = errno;
  }
#endif // #if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 4, 0)
#endif // #ifdef __linux__

exit:
  posix_spawnattr_destroy(&attr);
  posix_spawn_file_actions_destroy(&file_actions);
  return ret;
}

int moonbitlang_async_get_spawn_job_result_handle(struct spawn_job *job) {
  int result = job->pidfd;
  job->pidfd = -1;
  return result;
}

#endif // posix_spawn availability

struct spawn_job *moonbitlang_async_make_spawn_job(
  char *path,
  char **args,
  char **envp,
  int stdin_fd,
  int stdout_fd,
  int stderr_fd,
  int32_t is_orphan
) {
  struct spawn_job *job = MAKE_JOB(spawn, 0);
  job->path = path;
  job->args = args;
  job->envp = envp;
  job->stdio[0] = stdin_fd;
  job->stdio[1] = stdout_fd;
  job->stdio[2] = stderr_fd;
  job->cwd = 0;
  job->pidfd = -1;
  return job;
}

void moonbitlang_async_spawn_job_set_cwd(struct spawn_job *job, char *cwd) {
  job->cwd = cwd;
}

// Unix wait_for_process: blocking waitpid in worker thread
// Used as fallback when pidfd_open is not available (e.g. Android, older Linux)

struct wait_for_process_job {
  pid_t pid;
};

static
void free_wait_for_process_job(struct wait_for_process_job *job) {}

static
int32_t wait_for_process_job_worker(struct wait_for_process_job *job, int32_t *err_out) {
  int status;
  int ret = waitpid(job->pid, &status, 0);
  if (ret == job->pid) {
    return WEXITSTATUS(status);
  } else {
    *err_out = errno;
    return 0;
  }
}

struct wait_for_process_job *moonbitlang_async_make_wait_for_process_job(
  HANDLE handle,
  int32_t pid
) {
  struct wait_for_process_job *job = MAKE_JOB(wait_for_process, 0);
  job->pid = pid;
  return job;
}

#endif

// ===== bind job, bind socket to specific address =====
struct bind_job {
  HANDLE socket;
  struct sockaddr *addr;
};

static
void free_bind_job(struct bind_job *job) {
  moonbit_decref(job->addr);
}

static
int32_t bind_job_worker(struct bind_job *job, int32_t *err_out) {
  int32_t ret = bind((SOCKET)job->socket, job->addr, Moonbit_array_length(job->addr));

  if (ret < 0)
#ifdef _WIN32
    *err_out = GetLastError();
#else
    *err_out = errno;
#endif
  return ret;
}

MOONBIT_FFI_EXPORT
struct bind_job *moonbitlang_async_make_bind_job(HANDLE socket, struct sockaddr *addr) {
  struct bind_job *job = MAKE_JOB(bind, 0);
  job->socket = socket;
  job->addr = addr;
  return job;
}

// ===== getaddrinfo job, resolve host name via `getaddrinfo` =====

#ifdef _WIN32
typedef ADDRINFOW addrinfo_t;
#else
typedef struct addrinfo addrinfo_t;
#endif

struct getaddrinfo_job {
  char *hostname;
  addrinfo_t *result;
  int32_t result_fetched;
};

static
void free_getaddrinfo_job(struct getaddrinfo_job *job) {
  moonbit_decref(job->hostname);
  if (job->result && !job->result_fetched) {
#ifdef _WIN32
    FreeAddrInfoW(job->result);
#else
    freeaddrinfo(job->result);
#endif
  }
}

static
int32_t getaddrinfo_job_worker(struct getaddrinfo_job *job, int32_t *err_out) {
  addrinfo_t hint = {
    AI_ADDRCONFIG, // ai_flags
    AF_UNSPEC, // ai_family, support both IPv4 and IPv6
    0, // ai_socktype
    0, // ai_protocol
    0, 0, 0, 0
  };

#ifdef _WIN32
  int err = GetAddrInfoW(
    (LPCWSTR)job->hostname,
    0,
    &hint,
    &(job->result)
  );
  // https://learn.microsoft.com/en-us/windows/win32/api/ws2tcpip/nf-ws2tcpip-getaddrinfow#return-value
  switch (err) {
    case WSATRY_AGAIN:
    case WSANO_RECOVERY:
    case WSAEAFNOSUPPORT:
    case WSAHOST_NOT_FOUND:
    case WSATYPE_NOT_FOUND:
    case WSAESOCKTNOSUPPORT:
      return err;
    default:
      *err_out = err;
      return 0;
  }

#else

  int32_t ret = getaddrinfo(
    job->hostname,
    0,
    &hint,
    &(job->result)
  );
  if (ret == EAI_SYSTEM)
    *err_out = errno;
  return ret;

#endif
}

struct getaddrinfo_job *moonbitlang_async_make_getaddrinfo_job(char *hostname) {
  struct getaddrinfo_job *job = MAKE_JOB(getaddrinfo, 0);
  job->hostname = hostname;
  job->result = 0;
  job->result_fetched = 0;
  return job;
}

addrinfo_t *moonbitlang_async_get_getaddrinfo_result(struct getaddrinfo_job *job) {
  job->result_fetched = 1;
  return job->result;
}

#ifdef _WIN32

int interested_console_ctrl_event = 0;

BOOL WINAPI moonbitlang_async_console_control_handler(DWORD ctrl_type) {
  if (interested_console_ctrl_event & (1 << ctrl_type)) {
    PostQueuedCompletionStatus(
      pool.notify_send,
      ctrl_type | (1 << 31),
      (ULONG_PTR)pool.notify_recv,
      0
    );
    return TRUE;
  } else {
    return FALSE;
  }
}

#else // #ifdef _WIN32

// ===== sigwait job, wait for specific signal =====
struct sigwait_job {
  sigset_t signals;
};

static
void free_sigwait_job(struct sigwait_job *job) {}

static
int32_t sigwait_job_worker(struct sigwait_job *job, int32_t *err_out) {
  // Block all signals for the `sigwait` job.
  // Cancellation is performed via `SIGUSR2`, which is in the wait set.
  sigset_t all_signals, prev_mask;
  sigfillset(&all_signals);
  pthread_sigmask(SIG_SETMASK, &all_signals, &prev_mask);

  siginfo_t info;
  while (1) {
    int sig = 0;
    errno = 0;
    int err = sigwait(&job->signals, &sig);
    if (err > 0) {
      *err_out = err;
      goto cleanup;
    }

    if (sig == SIGUSR2)
      goto cleanup;

    // It seems that on MacOS, it is possible for `sigwait` to
    // silently return `0` without returning a signal,
    // and set `errno` to `EINTR`.
    // Handle this case here by retrying.
    if (sig == 0) {
      if (errno == EINTR || !errno) {
        continue;
      } else {
        *err_out = errno;
        goto cleanup;
      }
    }

    sig |= 1 << 31;
    do {
      if (write(pool.notify_send, &sig, sizeof(int)) > 0)
        goto cleanup;
    } while (errno == EINTR);
  }

cleanup:
  // Restore the mask of the worker thread, in case it get reused
  pthread_sigmask(SIG_SETMASK, &prev_mask, 0);
  return 0;
}

MOONBIT_FFI_EXPORT
struct sigwait_job *moonbitlang_async_make_sigwait_job(int *signals) {
  struct sigwait_job *job = MAKE_JOB(sigwait, 0);

  sigemptyset(&job->signals);
  for (int i = 0; i < Moonbit_array_length(signals); ++i) {
    if (signals[i] < 0) continue;
    sigaddset(&job->signals, signals[i]);
  }

  sigaddset(&job->signals, SIGUSR2);

  return job;
}

#endif // #ifndef _WIN32, sigwait job
