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


#include <pthread.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <dirent.h>
#include <spawn.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/stat.h>
#include <moonbit.h>

#ifdef __MACH__
#include <sys/event.h>
#define WAKEUP_METHOD_COND_VAR

#include <Availability.h>
#ifdef __MAC_OS_X_VERSION_MIN_REQUIRED
#if __MAC_OS_X_VERSION_MIN_REQUIRED >= 260000
#define posix_spawn_file_actions_addchdir_np posix_spawn_file_actions_addchdir
#endif
#endif

#else
#define WAKEUP_METHOD_SIGNAL
#endif

struct job {
  // an unique identifier for the job,
  // used to find the waiter of a job
  int32_t job_id;

  // data passed to job worker
  void *data;

  // the worker that actually performs the job.
  // it will receive `data` as parameter.
  void (*worker)(void *);
};

// =======================================================
// =================== the thread pool ===================
// =======================================================

struct {
  int initialized;

  int notify_send;

#ifdef WAKEUP_METHOD_SIGNAL
  sigset_t wakeup_signal;
  sigset_t old_sigmask;
#endif
} pool;

struct worker {
  pthread_t id;
  struct job job;
  int waiting;
#ifdef WAKEUP_METHOD_COND_VAR
  pthread_mutex_t mutex;
  pthread_cond_t cond;
#endif
};

static
void *worker_loop(void *data) {
  int sig;
  struct worker *self = (struct worker*)data;

  struct job job = self->job;

#ifdef WAKEUP_METHOD_COND_VAR
  pthread_mutex_init(&(self->mutex), 0);
  pthread_cond_init(&(self->cond), 0);
#endif

  while (job.worker) {
    int job_id = job.job_id;
    job.worker(job.data);

    self->waiting = 1;
    write(pool.notify_send, &job_id, sizeof(int));

#ifdef WAKEUP_METHOD_SIGNAL
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
    job = self->job;
  }
  return 0;
}

void moonbitlang_async_wake_worker(
  struct worker *worker,
  int32_t job_id,
  void *job_data,
  void (*job_worker)(void*)
) {
  moonbit_decref(worker->job.data);
  worker->job.job_id = job_id;
  worker->job.data = job_data;
  worker->job.worker = job_worker;
#ifdef WAKEUP_METHOD_SIGNAL
  pthread_kill(worker->id, SIGUSR1);
#elif defined(WAKEUP_METHOD_COND_VAR)
  pthread_mutex_lock(&(worker->mutex));
  worker->waiting = 0;
  pthread_cond_signal(&(worker->cond));
  pthread_mutex_unlock(&(worker->mutex));
#endif
}

void moonbitlang_async_init_thread_pool(int notify_send) {
  if (pool.initialized)
    abort();

#ifdef WAKEUP_METHOD_SIGNAL
  sigemptyset(&pool.wakeup_signal);
  sigaddset(&pool.wakeup_signal, SIGUSR1);
  pthread_sigmask(SIG_BLOCK, &pool.wakeup_signal, &pool.old_sigmask);
#endif

  sigset_t signals_to_block;
  sigemptyset(&signals_to_block);
  sigaddset(&signals_to_block, SIGCHLD);
  pthread_sigmask(SIG_BLOCK, &signals_to_block, 0);

  signal(SIGPIPE, SIG_IGN);

  pool.notify_send = notify_send;
  pool.initialized = 1;
}

void moonbitlang_async_destroy_thread_pool() {
  if (!pool.initialized)
    abort();

  pool.initialized = 0;

#ifdef WAKEUP_METHOD_SIGNAL
  pthread_sigmask(SIG_SETMASK, &pool.old_sigmask, 0);
#endif
}

void free_worker(void *target) {
  struct worker *worker = (struct worker*)target;
  // terminate the worker
  moonbitlang_async_wake_worker(worker, 0, 0, 0);
  pthread_join(worker->id, 0);
#ifdef WAKEUP_METHOD_COND_VAR
  pthread_mutex_destroy(&(worker->mutex));
  pthread_cond_destroy(&(worker->cond));
#endif
}

struct worker *moonbitlang_async_spawn_worker(
  int32_t init_job_id,
  void *init_job_data,
  void (*init_job_worker)(void*)
) {
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 512);

  struct worker *worker = (struct worker*)moonbit_make_external_object(
    &free_worker,
    sizeof(struct worker)
  );
  worker->job.job_id = init_job_id;
  worker->job.data = init_job_data;
  worker->job.worker = init_job_worker;
  worker->waiting = 0;
  pthread_create(&(worker->id), &attr, &worker_loop, worker);
  pthread_attr_destroy(&attr);
  return worker;
}

int32_t moonbitlang_async_fetch_completion(int notify_recv) {
  int job_id;
  int32_t ret = read(notify_recv, &job_id, sizeof(int));
  if (ret < 0)
    return ret;

  return job_id;
}

// =========================================================
// ===================== concrete jobs =====================
// =========================================================

// ===== sleep job, sleep via thread pool, for testing only =====

void moonbitlang_async_blocking_sleep(int32_t ms) {
  struct timespec duration;
  duration.tv_sec = ms / 1000;
  duration.tv_nsec = (ms % 1000) * 1000000;
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
}

// ===== spawn job, spawn foreign process =====

int32_t moonbitlang_async_spawn_process(
  char *path,
  char **args,
  char **envp,
  int stdin_fd,
  int stdout_fd,
  int stderr_fd,
  char *cwd
) {
  int32_t pid = -1;
  int32_t err = 0;
  posix_spawnattr_t attr;
  posix_spawnattr_init(&attr);
#ifdef WAKEUP_METHOD_SIGNAL
  posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);
  posix_spawnattr_setsigmask(&attr, &pool.old_sigmask);
#else
  posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSIGDEF);
#endif

  sigset_t sigdefault_set;
  sigemptyset(&sigdefault_set);
  sigaddset(&sigdefault_set, SIGCHLD);
  sigaddset(&sigdefault_set, SIGHUP);
  sigaddset(&sigdefault_set, SIGINT);
  sigaddset(&sigdefault_set, SIGQUIT);
  sigaddset(&sigdefault_set, SIGTERM);
  sigaddset(&sigdefault_set, SIGALRM);
  posix_spawnattr_setsigdefault(&attr, &sigdefault_set);

  posix_spawn_file_actions_t file_actions;
  posix_spawn_file_actions_init(&file_actions);

  int stdio_fd[3] = { stdin_fd, stdout_fd, stderr_fd };
  for (int i = 0; i < 3; ++i) {
    int fd = stdio_fd[i];
    if (fd >= 0) {
      err = posix_spawn_file_actions_adddup2(&file_actions, fd, i);
      if (err) goto exit;
    }
  }
  if (cwd) {
    err = posix_spawn_file_actions_addchdir_np(&file_actions, cwd);
    if (err) goto exit;
  }

  if (strchr(path, '/')) {
    err = posix_spawn(
      &pid,
      path,
      &file_actions,
      &attr,
      args,
      envp
    );
  } else {
    err = posix_spawnp(
      &pid,
      path,
      &file_actions,
      &attr,
      args,
      envp
    );
  }
exit:
  posix_spawnattr_destroy(&attr);
  posix_spawn_file_actions_destroy(&file_actions);
  if (err) {
    errno = err;
  }
  return pid;
}
