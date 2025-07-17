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
#include <errno.h>
#include <time.h>

enum op_code {
  OP_SLEEP = 0, // for testing only
  OP_READ,
  OP_WRITE,
  OP_OPEN
};

struct read_job {
  int fd;
  void *buf;
  int len;
};

struct write_job {
  int fd;
  void *buf;
  int len;
};

struct open_job {
  char *filename;
  int flags;
};

struct job {
  struct job *next;
  int32_t job_id;
  enum op_code op_code;
  union {
    struct timespec sleep;
    struct read_job read;
    struct write_job write;
    struct open_job open;
  } payload;
};

struct job_result {
  int32_t job_id;
  int32_t ret;
  int32_t err;
};


static
pthread_mutex_t pool_mutex = PTHREAD_MUTEX_INITIALIZER;

#define MAX_WORKER_COUNT 1024

struct {
  int initialized;

  int notify_send;
  int notify_recv;

  sigset_t wakeup_signal;
  sigset_t old_sigmask;
  int32_t job_id;

  // The following should be protected by `pool_mutex`
  struct job *job_queue_head;
  struct job *job_queue_tail;

  pthread_t workers[MAX_WORKER_COUNT];
  int worker_count;
  int free_worker_count;
} pool;

// thread unsafe
static
void enqueue_job(struct job *job) {
  if (pool.job_queue_tail) {
    pool.job_queue_tail->next = job;
    pool.job_queue_tail = job;
  } else {
    pool.job_queue_head = pool.job_queue_tail = job;
  }
}

// thread unsafe
static
struct job *dequeue_job() {
  struct job *job = pool.job_queue_head;
  if (job) {
    pool.job_queue_head = job->next;
    if (job == pool.job_queue_tail)
      pool.job_queue_tail = 0;
  }
  return job;
}

static
void *worker(void *data) {
  int sig;
  pthread_t self = pthread_self();

  sigset_t sigset;
  sigemptyset(&sigset);
  sigaddset(&sigset, SIGUSR1);

  struct job *job = (struct job*)data;

  while (1) {
    struct job_result result = { job->job_id, 0, 0 };
    switch (job->op_code) {
    case OP_SLEEP:
      nanosleep(&job->payload.sleep, 0);
      result.ret = 0;
      break;

    case OP_READ:
      result.ret = read(
        job->payload.read.fd,
        job->payload.read.buf,
        job->payload.read.len
      );
      if (result.ret < 0)
        result.err = errno;
      break;

    case OP_WRITE:
      result.ret = write(
        job->payload.read.fd,
        job->payload.read.buf,
        job->payload.read.len
      );
      if (result.ret < 0)
        result.err = errno;
      break;

    case OP_OPEN:
      result.ret = open(job->payload.open.filename, job->payload.open.flags);
      if (result.ret < 0)
        result.err = errno;
      break;
    }
    free(job);
    job = 0;
    write(pool.notify_send, &result, sizeof(struct job_result));

    while (1) {
      pthread_mutex_lock(&pool_mutex);
      job = dequeue_job();
      if (!job) {
        pool.workers[pool.free_worker_count++] = self;
      }
      pthread_mutex_unlock(&pool_mutex);

      if (job)
        break;

      sigwait(&pool.wakeup_signal, &sig);
    }
  }
  return 0;
}

int moonbitlang_async_init_thread_pool() {
  if (pool.initialized)
    abort();

  pool.job_id = 0;
  pool.job_queue_head = 0;
  pool.job_queue_tail = 0;
  pool.worker_count = 0;
  pool.free_worker_count = 0;

  int notification_pipe[2];
  if (0 != pipe(notification_pipe))
    return -1;

  for (int i = 0; i < 2; ++i) {
    // set the write end of the notification pipe as blocking,
    // and the read end as non-blocking
    int flags = fcntl(notification_pipe[i], F_GETFL);
    if (flags < 0) {
      close(notification_pipe[0]);
      close(notification_pipe[1]);
      return -1;
    }

    int new_flags = i == 0 ? flags | O_NONBLOCK : flags & ~O_NONBLOCK;
    if (flags != new_flags && 0 != fcntl(notification_pipe[i], F_SETFL, new_flags)) {
      close(notification_pipe[0]);
      close(notification_pipe[1]);
      return -1;
    }
  }

  pthread_mutex_init(&pool_mutex, 0);

  sigemptyset(&pool.wakeup_signal);
  sigaddset(&pool.wakeup_signal, SIGUSR1);
  pthread_sigmask(SIG_BLOCK, &pool.wakeup_signal, &pool.old_sigmask);

  pool.notify_recv = notification_pipe[0];
  pool.notify_send = notification_pipe[1];
  pool.initialized = 1;
  return pool.notify_recv;
}

void moonbitlang_async_destroy_thread_pool() {
  if (!pool.initialized)
    abort();

  pool.initialized = 0;

  pthread_mutex_destroy(&pool_mutex);

  pthread_sigmask(SIG_SETMASK, &pool.old_sigmask, 0);

  while (pool.job_queue_head) {
    struct job *head = pool.job_queue_head;
    pool.job_queue_head = head->next;
    free(head);
  }
  pool.job_queue_tail = 0;

  pool.job_id = 0;
  pool.worker_count = 0;
  pool.free_worker_count = 0;

  close(pool.notify_send);
  close(pool.notify_recv);
}

int moonbitlang_async_submit_job(struct job *job) {
  int id = job->job_id;
  pthread_mutex_lock(&pool_mutex);
  if (pool.free_worker_count > 0) {
    enqueue_job(job);
    pthread_t worker = pool.workers[--pool.free_worker_count];
    pthread_mutex_unlock(&pool_mutex);
    pthread_kill(worker, SIGUSR1);
  } else if (pool.worker_count >= MAX_WORKER_COUNT) {
    enqueue_job(job);
    pthread_mutex_unlock(&pool_mutex);
  } else {
    pthread_mutex_unlock(&pool_mutex);

    // no free worker thread available, try to spawn a new one
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 512);

    pthread_t id;
    pthread_create(&id, &attr, &worker, job);
    pthread_attr_destroy(&attr);
  }
  return id;
}

int moonbitlang_async_job_id(struct job *job) {
  return job->job_id;
}

struct job *moonbitlang_async_make_sleep_job(int ms) {
  struct job *job = (struct job*)malloc(sizeof(struct job));
  job->next = 0;
  job->job_id = pool.job_id++;
  job->op_code = OP_SLEEP;
  job->payload.sleep.tv_sec = ms / 1000;
  job->payload.sleep.tv_nsec = (ms % 1000) * 1000000;
  return job;
}

struct job *moonbitlang_async_make_read_job(int fd, void *buf, int len) {
  struct job *job = (struct job*)malloc(sizeof(struct job));
  job->next = 0;
  job->job_id = pool.job_id++;
  job->op_code = OP_READ;
  job->payload.read.fd = fd;
  job->payload.read.buf = buf;
  job->payload.read.len = len;
  return job;
}

struct job *moonbitlang_async_make_write_job(int fd, void *buf, int len) {
  struct job *job = (struct job*)malloc(sizeof(struct job));
  job->next = 0;
  job->job_id = pool.job_id++;
  job->op_code = OP_WRITE;
  job->payload.read.fd = fd;
  job->payload.read.buf = buf;
  job->payload.read.len = len;
  return job;
}

struct job *moonbitlang_async_make_open_job(char *filename, int flags) {
  struct job *job = (struct job*)malloc(sizeof(struct job));
  job->next = 0;
  job->job_id = pool.job_id++;
  job->op_code = OP_OPEN;
  job->payload.open.filename = filename;
  job->payload.open.flags = flags;
  return job;
}

int moonbitlang_async_fetch_completion(struct job_result *result) {
  int ret = read(pool.notify_recv, result, sizeof(struct job_result));
  if (ret < 0)
    return ret;

  // should not happer, must be a bug
  if (ret < sizeof(struct job_result))
    abort();

  return 0;
}
