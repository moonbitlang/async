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
  // the return value of the job.
  // should be set by the worker and read by waiter.
  // for result that cannot fit in an integer,
  // jobs can also store extra result in their payload
  int32_t ret;

  // the error code of the job.
  // should be zefo iff the job succeeds
  int32_t err;

  // the worker that actually performs the job.
  // it will receive the job itself as parameter.
  // extra payload can be placed after the header fields in `struct job`
  void (*worker)(struct job*);
};

int64_t moonbitlang_async_job_get_ret(struct job *job) {
  return job->ret;
}

int32_t moonbitlang_async_job_get_err(struct job *job) {
  return job->err;
}

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


// The type for a worker thread
struct worker {
  pthread_t id;

  // an unique identifier for current job,
  // used to find the waiter of a job
  int32_t job_id;

  // the job currently being processed
  struct job *job;

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

  int job_id = self->job_id;
  struct job *job = self->job;

#ifdef WAKEUP_METHOD_COND_VAR
  pthread_mutex_init(&(self->mutex), 0);
  pthread_cond_init(&(self->cond), 0);
#endif

  while (job) {
    job->ret = 0;
    job->err = 0;

    job->worker(job);

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
    job_id = self->job_id;
    job = self->job;
  }
  return 0;
}

void moonbitlang_async_wake_worker(
  struct worker *worker,
  int32_t job_id,
  struct job *job
) {
  moonbit_decref(worker->job);
  worker->job_id = job_id;
  worker->job = job;
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
  moonbitlang_async_wake_worker(worker, 0, 0);
  pthread_join(worker->id, 0);
#ifdef WAKEUP_METHOD_COND_VAR
  pthread_mutex_destroy(&(worker->mutex));
  pthread_cond_destroy(&(worker->cond));
#endif
}

struct worker *moonbitlang_async_spawn_worker(
  int32_t init_job_id,
  struct job *init_job
) {
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 512);

  struct worker *worker = (struct worker*)moonbit_make_external_object(
    &free_worker,
    sizeof(struct worker)
  );
  worker->job_id = init_job_id;
  worker->job = init_job;
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

static
struct job *make_job(
  int32_t size,
  void (*free_job)(void*),
  void (*worker)(struct job*)
) {
  struct job *job = (struct job*)moonbit_make_external_object(
    free_job,
    size
  );
  job->ret = 0;
  job->err = 0;
  job->worker = worker;
  return job;
}

#define MAKE_JOB(name) (struct name##_job*)make_job(\
  sizeof(struct name##_job),\
  free_##name##_job,\
  name##_job_worker\
)

// ===== sleep job, sleep via thread pool, for testing only =====

struct sleep_job {
  struct job job;
  struct timespec duration;
};

static
void free_sleep_job(void *job) {}

static
void sleep_job_worker(struct job *job) {
  struct timespec duration = ((struct sleep_job*)job)->duration;
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

struct sleep_job *moonbitlang_async_make_sleep_job(int ms) {
  struct sleep_job *job = MAKE_JOB(sleep);
  job->duration.tv_sec = ms / 1000;
  job->duration.tv_nsec = (ms % 1000) * 1000000;
  return job;
}

// ===== read job, for reading non-pollable stuff =====

struct read_job {
  struct job job;
  int fd;
  char *buf;
  int offset;
  int len;
  int64_t position;
};

static
void free_read_job(void *obj) {
  struct read_job *job = (struct read_job*)obj;
  moonbit_decref(job->buf);
}

static
void read_job_worker(struct job *job) {
  struct read_job *read_job = (struct read_job*)job;
  if (read_job->position < 0) {
    job->ret = read(read_job->fd, read_job->buf + read_job->offset, read_job->len);
  } else {
    job->ret = pread(
      read_job->fd,
      read_job->buf + read_job->offset,
      read_job->len,
      read_job->position
    );
  }
  if (job->ret < 0)
    job->err = errno;
}

struct read_job *moonbitlang_async_make_read_job(
  int fd,
  char *buf,
  int offset,
  int len,
  int64_t position
) {
  struct read_job *job = MAKE_JOB(read);
  job->fd = fd;
  job->buf = buf;
  job->offset = offset;
  job->len = len;
  job->position = position;
  return job;
}

// ===== write job, for writing non-pollable stuff =====

struct write_job {
  struct job job;
  int fd;
  char *buf;
  int offset;
  int len;
  int64_t position;
};

static
void free_write_job(void *obj) {
  struct write_job *job = (struct write_job*)obj;
  moonbit_decref(job->buf);
}

static
void write_job_worker(struct job *job) {
  struct write_job *write_job = (struct write_job*)job;
  if (write_job->position < 0) {
    job->ret = write(
      write_job->fd,
      write_job->buf + write_job->offset,
      write_job->len
    );
  } else {
    job->ret = pwrite(
      write_job->fd,
      write_job->buf + write_job->offset,
      write_job->len,
      write_job->position
    );
  }
  if (job->ret < 0)
    job->err = errno;
}

struct write_job *moonbitlang_async_make_write_job(
  int fd,
  char *buf,
  int offset,
  int len,
  int64_t position
) {
  struct write_job *job = MAKE_JOB(write);
  job->fd = fd;
  job->buf = buf;
  job->offset = offset;
  job->len = len;
  job->position = position;
  return job;
}

// ===== open job =====

struct open_job {
  struct job job;
  char *filename;
  int flags;
  int mode;
  mode_t kind;
};

static
void free_open_job(void *obj) {
  struct open_job *job = (struct open_job*)obj;
  moonbit_decref(job->filename);
}

static
void open_job_worker(struct job *job) {
  struct open_job *open_job = (struct open_job*)job;
  job->ret = open(
    open_job->filename,
    open_job->flags | O_CLOEXEC,
    open_job->mode
  );
  if (job->ret < 0) {
    job->err = errno;
    return;
  }
  struct stat stat;
  if (fstat(job->ret, &stat) < 0) {
    job->err = errno;
    return;
  }
  open_job->kind = stat.st_mode;
}

struct open_job *moonbitlang_async_make_open_job(
  char *filename,
  int access,
  int create,
  int append,
  int truncate,
  int sync,
  int mode
) {
  static int access_flags[] = { O_RDONLY, O_WRONLY, O_RDWR };
  static int sync_flags[] = { 0, O_DSYNC, O_SYNC };

  struct open_job *job = MAKE_JOB(open);
  job->filename = filename;
  job->flags = access_flags[access] | sync_flags[sync];
  if (create) job->flags |= O_CREAT;
  if (append) job->flags |= O_APPEND;
  if (truncate) job->flags |= O_TRUNC;
  job->mode = mode;
  return job;
}

int32_t moonbitlang_async_get_open_job_kind(struct open_job *job) {
  return job->kind;
}

// ===== file kind by path job, get kind of path on file system =====

struct file_kind_by_path_job {
  struct job job;
  char *path;
  int follow_symlink;
};

static
void free_file_kind_by_path_job(void *obj) {
  struct file_kind_by_path_job *job = (struct file_kind_by_path_job*)obj;
  moonbit_decref(job->path);
}

static
void file_kind_by_path_job_worker(struct job *job) {
  struct file_kind_by_path_job *file_kind_by_path_job = (struct file_kind_by_path_job*)job;
  struct stat stat_obj;
  if (file_kind_by_path_job->follow_symlink) {
    job->ret = stat(file_kind_by_path_job->path, &stat_obj);
  } else {
    job->ret = lstat(file_kind_by_path_job->path, &stat_obj);
  }
  if (job->ret < 0) {
    job->err = errno;
  } else {
    job->ret = stat_obj.st_mode;
  }
}

struct file_kind_by_path_job *moonbitlang_async_make_file_kind_by_path_job(
  char *path,
  int follow_symlink
) {
  struct file_kind_by_path_job *job = MAKE_JOB(file_kind_by_path);
  job->path = path;
  job->follow_symlink = follow_symlink;
  return job;
}

// ===== file size job, get size of opened file =====

struct file_size_job {
  struct job job;
  int fd;
  int64_t result;
};

static
void free_file_size_job(void *obj) {}

static
void file_size_job_worker(struct job *job) {
  struct file_size_job *file_size_job = (struct file_size_job*)job;
  struct stat stat;
  job->ret = fstat(file_size_job->fd, &stat);
  if (job->ret < 0) {
    job->err = errno;
  } else {
    file_size_job->result = stat.st_size;
  }
}

struct file_size_job *moonbitlang_async_make_file_size_job(int fd) {
  struct file_size_job *job = MAKE_JOB(file_size);
  job->fd = fd;
  return job;
}

int64_t moonbitlang_async_get_file_size_result(struct file_size_job *job) {
  return job->result;
}

// ===== file time job, get timestamp of opened file =====

struct file_time_job {
  struct job job;
  int fd;
  void *out;
};

static
void free_file_time_job(void *obj) {
  struct file_time_job *job = (struct file_time_job*)obj;
  moonbit_decref(job->out);
}

static
void file_time_job_worker(struct job *job) {
  struct file_time_job *file_time_job = (struct file_time_job*)job;
  job->ret = fstat(file_time_job->fd, file_time_job->out);
  if (job->ret < 0)
    job->err = errno;
}

struct file_time_job *moonbitlang_async_make_file_time_job(int fd, void *out) {
  struct file_time_job *job = MAKE_JOB(file_time);
  job->fd = fd;
  job->out = out;
  return job;
}

// ===== file time by path job, get timestamp of path on file system =====

struct file_time_by_path_job {
  struct job job;
  char *path;
  void *out;
  int follow_symlink;
};

static
void free_file_time_by_path_job(void *obj) {
  struct file_time_by_path_job *job = (struct file_time_by_path_job*)obj;
  moonbit_decref(job->path);
  moonbit_decref(job->out);
}

static
void file_time_by_path_job_worker(struct job *job) {
  struct file_time_by_path_job *file_time_by_path_job = (struct file_time_by_path_job*)job;
  if (file_time_by_path_job->follow_symlink) {
    job->ret = stat(file_time_by_path_job->path, file_time_by_path_job->out);
  } else {
    job->ret = lstat(file_time_by_path_job->path, file_time_by_path_job->out);
  }
  if (job->ret < 0)
    job->err = errno;
}

struct file_time_by_path_job *moonbitlang_async_make_file_time_by_path_job(
  char *path,
  void *out,
  int follow_symlink
) {
  struct file_time_by_path_job *job = MAKE_JOB(file_time_by_path);
  job->path = path;
  job->out = out;
  job->follow_symlink = follow_symlink;
  return job;
}

// ===== access job, test permission of file path =====

struct access_job {
  struct job job;
  char *path;
  int amode;
};

static
void free_access_job(void *obj) {
  struct access_job *job = (struct access_job*)obj;
  moonbit_decref(job->path);
}

static
void access_job_worker(struct job *job) {
  struct access_job *access_job = (struct access_job*)job;
  job->ret = access(access_job->path, access_job->amode);
  if (job->ret < 0)
    job->err = errno;
}

struct access_job *moonbitlang_async_make_access_job(char *path, int amode) {
  struct access_job *job = MAKE_JOB(access);
  job->path = path;
  job->amode = amode;
  return job;
}

// ===== chmod job, change permission of file =====

struct chmod_job {
  struct job job;
  char *path;
  mode_t mode;
};

static
void free_chmod_job(void *obj) {
  struct chmod_job *job = (struct chmod_job*)obj;
  moonbit_decref(job->path);
}

static
void chmod_job_worker(struct job *job) {
  struct chmod_job *chmod_job = (struct chmod_job*)job;
  job->ret = chmod(chmod_job->path, chmod_job->mode);
  if (job->ret < 0)
    job->err = errno;
}

struct chmod_job *moonbitlang_async_make_chmod_job(char *path, int mode) {
  struct chmod_job *job = MAKE_JOB(chmod);
  job->path = path;
  job->mode = mode;
  return job;
}

 
// ===== fsync job, synchronize file modification to disk =====

struct fsync_job {
  struct job job;
  int fd;
  int only_data;
};

static
void free_fsync_job(void *obj) {}

static
void fsync_job_worker(struct job *job) {
  struct fsync_job *fsync_job = (struct fsync_job*)job;
#ifdef __MACH__
  // it seems that `fdatasync` is not available on some MacOS versions
  job->ret = fsync(fsync_job->fd);
#else
  if (fsync_job->only_data) {
    job->ret = fdatasync(fsync_job->fd);
  } else {
    job->ret = fsync(fsync_job->fd);
  }
#endif
  if (job->ret < 0)
    job->err = errno;
}

struct fsync_job *moonbitlang_async_make_fsync_job(int fd, int only_data) {
  struct fsync_job *job = MAKE_JOB(fsync);
  job->fd = fd;
  job->only_data = only_data;
  return job;
}

// ===== remove job, remove file from file system =====

struct remove_job {
  struct job job;
  char *path;
};

static
void free_remove_job(void *obj) {
  struct remove_job *job = (struct remove_job*)obj;
  moonbit_decref(job->path);
}

static
void remove_job_worker(struct job *job) {
  struct remove_job *remove_job = (struct remove_job*)job;
  job->ret = remove(remove_job->path);
  if (job->ret < 0)
    job->err = errno;
}

struct remove_job *moonbitlang_async_make_remove_job(char *path) {
  struct remove_job *job = MAKE_JOB(remove);
  job->path = path;
  return job;
}

// ===== symlink job, create symbolic link =====

struct symlink_job {
  struct job job;
  char *target;
  char *path;
};

static
void free_symlink_job(void *obj) {
  struct symlink_job *job = (struct symlink_job*)obj;
  moonbit_decref(job->target);
  moonbit_decref(job->path);
}

static
void symlink_job_worker(struct job *job) {
  struct symlink_job *symlink_job = (struct symlink_job*)job;
  job->ret = symlink(symlink_job->target, symlink_job->path);
  if (job->ret < 0)
    job->err = errno;
}

struct symlink_job *moonbitlang_async_make_symlink_job(char *target, char *path) {
  struct symlink_job *job = MAKE_JOB(symlink);
  job->target = target;
  job->path = path;
  return job;
}


// ===== mkdir job, create new directory =====

struct mkdir_job {
  struct job job;
  char *path;
  int mode;
};

static
void free_mkdir_job(void *obj) {
  struct mkdir_job *job = (struct mkdir_job*)obj;
  moonbit_decref(job->path);
}

static
void mkdir_job_worker(struct job *job) {
  struct mkdir_job *mkdir_job = (struct mkdir_job*)job;
  job->ret = mkdir(mkdir_job->path, mkdir_job->mode);
  if (job->ret < 0)
    job->err = errno;
}

struct mkdir_job *moonbitlang_async_make_mkdir_job(char *path, int mode) {
  struct mkdir_job *job = MAKE_JOB(mkdir);
  job->path = path;
  job->mode = mode;
  return job;
}

// ===== rmdir job, remove directory =====

struct rmdir_job {
  struct job job;
  char *path;
};

static
void free_rmdir_job(void *obj) {
  struct rmdir_job *job = (struct rmdir_job*)obj;
  moonbit_decref(job->path);
}

static
void rmdir_job_worker(struct job *job) {
  struct rmdir_job *rmdir_job = (struct rmdir_job*)job;
  job->ret = rmdir(rmdir_job->path);
  if (job->ret < 0)
    job->err = errno;
}

struct rmdir_job *moonbitlang_async_make_rmdir_job(char *path) {
  struct rmdir_job *job = MAKE_JOB(rmdir);
  job->path = path;
  return job;
}

// ===== opendir job, open directory =====

struct opendir_job {
  struct job job;
  char *path;
  DIR *result;

  // if the waiter is cancelled before `opendir` succeed,
  // we need to call `closedir` to free resource on the result.
  // however, if the waiter is not cancelled,
  // the ownership of the result should be transferred to the waiter.
  // here we use a flag `result_fetched` to determine which case it is.
  int result_fetched;
};

static
void free_opendir_job(void *obj) {
  struct opendir_job *job = (struct opendir_job*)obj;
  moonbit_decref(job->path);
  if (job->result && !(job->result_fetched))
    closedir(job->result);
}

static
void opendir_job_worker(struct job *job) {
  struct opendir_job *opendir_job = (struct opendir_job*)job;
  opendir_job->result = opendir(opendir_job->path);
  if (!(opendir_job->result)) {
    job->err = errno;
  }
}

struct opendir_job *moonbitlang_async_make_opendir_job(char *path) {
  struct opendir_job *job = MAKE_JOB(opendir);
  job->path = path;
  job->result_fetched = 0;
  return job;
}

DIR *moonbitlang_async_get_opendir_result(struct opendir_job *job) {
  job->result_fetched = 1;
  return job->result;
}

// ===== readdir job, read directory entry =====

struct readdir_job {
  struct job job;
  DIR *dir;
  struct dirent *result;
};

static
void free_readdir_job(void *obj) {}

static
void readdir_job_worker(struct job *job) {
  struct readdir_job *readdir_job = (struct readdir_job*)job;
  errno = 0;
  readdir_job->result = readdir(readdir_job->dir);
  if (readdir_job->result == 0 && errno) {
    job->ret = -1;
    job->err = errno;
  }
}

struct readdir_job *moonbitlang_async_make_readdir_job(DIR *dir) {
  struct readdir_job *job = MAKE_JOB(readdir);
  job->dir = dir;
  return job;
}

char *moonbitlang_async_get_readdir_result(struct readdir_job *job) {
  return job->result ? job->result->d_name : 0;
}

// ===== realpath job, get canonical representation of a path =====

struct realpath_job {
  struct job job;
  char *path;
  char *result;
};

static
void free_realpath_job(void *obj) {
  struct realpath_job *job = (struct realpath_job*)obj;
  moonbit_decref(job->path);
}

static
void realpath_job_worker(struct job *job) {
  struct realpath_job *realpath_job = (struct realpath_job*)job;
  realpath_job->result = realpath(realpath_job->path, 0);
  if (!realpath_job->result) {
    job->ret = -1;
    job->err = errno;
  }
}

struct realpath_job *moonbitlang_async_make_realpath_job(char *path) {
  struct realpath_job *job = MAKE_JOB(realpath);
  job->path = path;
  return job;
}

char *moonbitlang_async_get_realpath_result(struct realpath_job *job) {
  return job->result;
}

// ===== spawn job, spawn foreign process =====

struct spawn_job {
  struct job job;
  char *path;
  char **args;
  char **envp;
  int stdio[3];
  char *cwd;
};

static
void free_spawn_job(void *obj) {
  struct spawn_job *job = (struct spawn_job*)obj;
  moonbit_decref(job->path);
  moonbit_decref(job->args);
  moonbit_decref(job->envp);
  if (job->cwd)
    moonbit_decref(job->cwd);
}

static
void spawn_job_worker(struct job *job) {
  struct spawn_job *spawn_job = (struct spawn_job *)job;
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
  for (int i = 0; i < 3; ++i) {
    int fd = spawn_job->stdio[i];
    if (fd >= 0) {
      job->err = posix_spawn_file_actions_adddup2(&file_actions, fd, i);
      if (job->err) goto exit;
    }
  }
  if (spawn_job->cwd) {
    job->err = posix_spawn_file_actions_addchdir_np(&file_actions, spawn_job->cwd);
    if (job->err) goto exit;
  }

  if (strchr(spawn_job->path, '/')) {
    job->err = posix_spawn(
      &(job->ret),
      spawn_job->path,
      &file_actions,
      &attr,
      spawn_job->args,
      spawn_job->envp
    );
  } else {
    job->err = posix_spawnp(
      &(job->ret),
      spawn_job->path,
      &file_actions,
      &attr,
      spawn_job->args,
      spawn_job->envp
    );
  }
exit:
  posix_spawnattr_destroy(&attr);
  posix_spawn_file_actions_destroy(&file_actions);
}

struct spawn_job *moonbitlang_async_make_spawn_job(
  char *path,
  char **args,
  char **envp,
  int stdin_fd,
  int stdout_fd,
  int stderr_fd,
  char *cwd
) {
  struct spawn_job *job = MAKE_JOB(spawn);
  job->path = path;
  job->args = args;
  job->envp = envp;
  job->stdio[0] = stdin_fd;
  job->stdio[1] = stdout_fd;
  job->stdio[2] = stderr_fd;
  job->cwd = cwd;
  return job;
}

// ===== getaddrinfo job, resolve host name via `getaddrinfo` =====

struct getaddrinfo_job {
  struct job job;
  char *hostname;
  struct addrinfo *result;
};

static
void free_getaddrinfo_job(void *obj) {
  struct getaddrinfo_job *job = (struct getaddrinfo_job*)obj;
  moonbit_decref(job->hostname);
}

static
void getaddrinfo_job_worker(struct job *job) {
  struct getaddrinfo_job *getaddrinfo_job = (struct getaddrinfo_job*)job;
  struct addrinfo hint = {
    AI_ADDRCONFIG, // ai_flags
    AF_UNSPEC, // ai_family, support both IPv4 and IPv6
    0, // ai_socktype
    0, // ai_protocol
    0, 0, 0, 0
  };
  job->ret = getaddrinfo(
    getaddrinfo_job->hostname, 
    0,
    &hint,
    &(getaddrinfo_job->result)
  );
  if (job->ret == EAI_SYSTEM)
    job->err = errno;
}

struct getaddrinfo_job *moonbitlang_async_make_getaddrinfo_job(char *hostname) {
  struct getaddrinfo_job *job = MAKE_JOB(getaddrinfo);
  job->hostname = hostname;
  return job;
}

struct addrinfo *moonbitlang_async_get_getaddrinfo_result(struct getaddrinfo_job *job) {
  return job->result;
}
