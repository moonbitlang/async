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
#ifdef __MAC_OS_X_VERSION_MAX_ALLOWED
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
#define posix_spawn_file_actions_addchdir_np posix_spawn_file_actions_addchdir
#endif
#endif

#else
#define WAKEUP_METHOD_SIGNAL
#endif

extern char **environ;

enum op_code {
  OP_SLEEP = 0, // for testing only
  OP_READ,
  OP_WRITE,
  OP_OPEN,
  OP_STAT,
  OP_ACCESS,
  OP_REMOVE,
  OP_MKDIR,
  OP_RMDIR,
  OP_READDIR,
  OP_REALPATH,
  OP_SPAWN,
  OP_GETADDRINFO
};

struct read_job {
  int fd;
  char *buf;
  int offset;
  int len;
};

struct write_job {
  int fd;
  char *buf;
  int offset;
  int len;
};

struct open_job {
  char *filename;
  int flags;
  int mode;
};

struct stat_job {
  char *path;
  void *out;
  int follow_symlink;
};

struct access_job {
  char *path;
  int amode;
};

struct remove_job {
  char *path;
};

struct mkdir_job {
  char *path;
  int mode;
};

struct rmdir_job {
  char *path;
};

struct readdir_job {
  DIR *dir;
  struct dirent **out;
};

struct realpath_job {
  char *path;
  char **out;
};

struct spawn_job {
  char *path;
  char **args;
  char **envp;
  int stdio[3];
  char *cwd;
};

struct getaddrinfo_job {
  char *hostname;
  struct addrinfo **out;
};

struct job {
  int32_t job_id;
  enum op_code op_code;
  int32_t ret;
  int32_t err;
  union {
    struct timespec sleep;
    struct read_job read;
    struct write_job write;
    struct open_job open;
    struct stat_job stat;
    struct access_job access;
    struct remove_job remove;
    struct mkdir_job mkdir;
    struct rmdir_job rmdir;
    struct readdir_job readdir;
    struct realpath_job realpath;
    struct spawn_job spawn;
    struct getaddrinfo_job getaddrinfo;
  } payload;
};

struct {
  int initialized;

  int notify_send;

#ifdef WAKEUP_METHOD_SIGNAL
  sigset_t wakeup_signal;
  sigset_t old_sigmask;
#endif
  int32_t job_id;
} pool;

int32_t moonbitlang_async_job_get_id(struct job *job) {
  return job->job_id;
}

int32_t moonbitlang_async_job_get_ret(struct job *job) {
  return job->ret;
}

int32_t moonbitlang_async_job_get_err(struct job *job) {
  return job->err;
}

int32_t moonbitlang_async_job_poll_event(struct job *job) {
  switch (job->op_code) {
  case OP_READ: return 1;
  case OP_WRITE: return 2;
  default: return 0;
  }
}

int moonbitlang_async_job_poll_fd(struct job *job) {
  switch (job->op_code) {
  case OP_READ: return job->payload.read.fd;
  case OP_WRITE: return job->payload.write.fd;
  default: return -1;
  }
}

struct worker {
  pthread_t id;
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

  struct job *job = self->job;

#ifdef WAKEUP_METHOD_COND_VAR
  pthread_mutex_init(&(self->mutex), 0);
  pthread_cond_init(&(self->cond), 0);
#endif

  while (job) {
    job->ret = 0;
    job->err = 0;

    switch (job->op_code) {
    case OP_SLEEP:
#ifdef __MACH__
      {
        // On GitHub CI MacOS runner, `nanosleep` is very imprecise,
        // causing corrupted test result.
        // However `kqueue` seems to have very accurate timing.
        // Since `OP_SLEEP` is only for testing purpose,
        // here we use `kqueue` (in an absolutely wrong way) to perform sleep.
        int kqfd = kqueue();
        struct kevent kev;
        kevent(kqfd, 0, 0, &kev, 1, &(job->payload.sleep));
        close(kqfd);
      }
#else
      nanosleep(&job->payload.sleep, 0);
#endif
      job->ret = 0;
      break;

    case OP_READ:
      job->ret = read(
        job->payload.read.fd,
        job->payload.read.buf + job->payload.read.offset,
        job->payload.read.len
      );
      if (job->ret < 0)
        job->err = errno;
      break;

    case OP_WRITE:
      job->ret = write(
        job->payload.write.fd,
        job->payload.write.buf + job->payload.write.offset,
        job->payload.write.len
      );
      if (job->ret < 0)
        job->err = errno;
      break;

    case OP_OPEN:
      job->ret = open(
        job->payload.open.filename,
        job->payload.open.flags | O_CLOEXEC,
        job->payload.open.mode
      );
      if (job->ret < 0)
        job->err = errno;
      break;

    case OP_STAT:
      if (job->payload.stat.follow_symlink) {
        job->ret = stat(job->payload.stat.path, job->payload.stat.out);
      } else {
        job->ret = lstat(job->payload.stat.path, job->payload.stat.out);
      }
      if (job->ret < 0)
        job->err = errno;
      break;

    case OP_ACCESS:
      job->ret = access(job->payload.access.path, job->payload.access.amode);
      if (job->ret < 0)
        job->err = errno;
      break;

    case OP_REMOVE:
      job->ret = remove(job->payload.remove.path);
      if (job->ret < 0)
        job->err = errno;
      break;

    case OP_MKDIR:
      job->ret = mkdir(job->payload.mkdir.path, job->payload.mkdir.mode);
      if (job->ret < 0)
        job->err = errno;
      break;

    case OP_RMDIR:
      job->ret = rmdir(job->payload.rmdir.path);
      if (job->ret < 0)
        job->err = errno;
      break;

    case OP_READDIR:
      errno = 0;
      *(job->payload.readdir.out) = readdir(job->payload.readdir.dir);
      if (*(job->payload.readdir.out) == 0 && errno) {
        job->ret = -1;
        job->err = errno;
      }
      break;

    case OP_REALPATH: {
      *(job->payload.realpath.out) = 0;
      *(job->payload.realpath.out) = realpath(job->payload.realpath.path, 0);
      if (*(job->payload.realpath.out) == 0) {
        job->ret = -1;
        job->err = errno;
      }
      break;
    }

    case OP_SPAWN: {
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
        int fd = job->payload.spawn.stdio[i];
        if (fd >= 0) {
          job->err = posix_spawn_file_actions_adddup2(&file_actions, fd, i);
          if (job->err) goto exit;
        }
      }
      if (job->payload.spawn.cwd) {
        job->err = posix_spawn_file_actions_addchdir_np(&file_actions, job->payload.spawn.cwd);
        if (job->err) goto exit;
      }

      int32_t pid;
      if (strchr(job->payload.spawn.path, '/')) {
        job->err = posix_spawn(
          &pid,
          job->payload.spawn.path,
          &file_actions,
          &attr,
          job->payload.spawn.args,
          job->payload.spawn.envp ? job->payload.spawn.envp : environ
        );
      } else {
        job->err = posix_spawnp(
          &pid,
          job->payload.spawn.path,
          &file_actions,
          &attr,
          job->payload.spawn.args,
          job->payload.spawn.envp ? job->payload.spawn.envp : environ
        );
      }
    exit:
      posix_spawnattr_destroy(&attr);
      posix_spawn_file_actions_destroy(&file_actions);
      if (!(job->err)) {
        job->ret = pid;
      }
      break;
    }

    case OP_GETADDRINFO: {
      struct addrinfo hint = {
        AI_ADDRCONFIG, // ai_flags
        AF_UNSPEC, // ai_family, support both IPv4 and IPv6
        0, // ai_socktype
        0, // ai_protocol
        0, 0, 0, 0
      };
      job->ret = getaddrinfo(
        job->payload.getaddrinfo.hostname, 
        0,
        &hint,
        job->payload.getaddrinfo.out
      );
      if (job->ret == EAI_SYSTEM)
        job->err = errno;
      break;
    }
    }
    self->waiting = 1;
    write(pool.notify_send, &(job->job_id), sizeof(int));

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

void moonbitlang_async_wake_worker(struct worker *worker, struct job *job) {
  moonbit_decref(worker->job);
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

  pool.job_id = 0;

#ifdef WAKEUP_METHOD_SIGNAL
  sigemptyset(&pool.wakeup_signal);
  sigaddset(&pool.wakeup_signal, SIGUSR1);
  pthread_sigmask(SIG_BLOCK, &pool.wakeup_signal, &pool.old_sigmask);
#endif

  sigset_t sigpipe;
  sigemptyset(&sigpipe);
  sigaddset(&sigpipe, SIGPIPE);
  sigaddset(&sigpipe, SIGCHLD);
  pthread_sigmask(SIG_BLOCK, &sigpipe, 0);

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

  pool.job_id = 0;
}

void free_worker(void *target) {
  struct worker *worker = (struct worker*)target;
  // terminate the worker
  moonbitlang_async_wake_worker(worker, 0);
  pthread_join(worker->id, 0);
#ifdef WAKEUP_METHOD_COND_VAR
  pthread_mutex_destroy(&(worker->mutex));
  pthread_cond_destroy(&(worker->cond));
#endif
}

struct worker *moonbitlang_async_spawn_worker(struct job *init_job) {
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 512);

  struct worker *worker = (struct worker*)moonbit_make_external_object(
    &free_worker,
    sizeof(struct worker)
  );
  worker->job = init_job;
  worker->waiting = 0;
  pthread_create(&(worker->id), &attr, &worker_loop, worker);
  pthread_attr_destroy(&attr);
  return worker;
}

int moonbitlang_async_job_id(struct job *job) {
  return job->job_id;
}

static
void free_job(void *jobp) {
  struct job *job = (struct job*)jobp;
  switch (job->op_code) {
  case OP_SLEEP: break;
  case OP_READ:
    moonbit_decref(job->payload.read.buf);
    break;
  case OP_WRITE:
    moonbit_decref(job->payload.write.buf);
    break;
  case OP_OPEN:
    moonbit_decref(job->payload.open.filename);
    break;
  case OP_STAT:
    moonbit_decref(job->payload.stat.path);
    moonbit_decref(job->payload.stat.out);
    break;
  case OP_ACCESS:
    moonbit_decref(job->payload.access.path);
    break;
  case OP_REMOVE:
    moonbit_decref(job->payload.remove.path);
    break;
  case OP_MKDIR:
    moonbit_decref(job->payload.mkdir.path);
    break;
  case OP_RMDIR:
    moonbit_decref(job->payload.rmdir.path);
    break;
  case OP_READDIR:
    moonbit_decref(job->payload.readdir.out);
    break;
  case OP_REALPATH:
    moonbit_decref(job->payload.realpath.path);
    moonbit_decref(job->payload.realpath.out);
    break;
  case OP_SPAWN:
    moonbit_decref(job->payload.spawn.path);
    moonbit_decref(job->payload.spawn.args);
    moonbit_decref(job->payload.spawn.envp);
    if (job->payload.spawn.cwd)
      moonbit_decref(job->payload.spawn.cwd);
    break;
  case OP_GETADDRINFO:
    moonbit_decref(job->payload.getaddrinfo.hostname);
    moonbit_decref(job->payload.getaddrinfo.out);
    break;
  }
}

static
struct job *make_job() {
  struct job *job = (struct job*)moonbit_make_external_object(
    &free_job,
    sizeof(struct job)
  );
  job->ret = 0;
  job->err = 0;
  return job;
}

struct job *moonbitlang_async_make_sleep_job(int ms) {
  struct job *job = make_job();
  job->job_id = pool.job_id++;
  job->op_code = OP_SLEEP;
  job->payload.sleep.tv_sec = ms / 1000;
  job->payload.sleep.tv_nsec = (ms % 1000) * 1000000;
  return job;
}

struct job *moonbitlang_async_make_read_job(int fd, char *buf, int offset, int len) {
  struct job *job = make_job();
  job->job_id = pool.job_id++;
  job->op_code = OP_READ;
  job->payload.read.fd = fd;
  job->payload.read.buf = buf;
  job->payload.read.offset = offset;
  job->payload.read.len = len;
  return job;
}

struct job *moonbitlang_async_make_write_job(int fd, char *buf, int offset, int len) {
  struct job *job = make_job();
  job->job_id = pool.job_id++;
  job->op_code = OP_WRITE;
  job->payload.read.fd = fd;
  job->payload.read.buf = buf;
  job->payload.read.offset = offset;
  job->payload.read.len = len;
  return job;
}

struct job *moonbitlang_async_make_open_job(char *filename, int flags, int mode) {
  struct job *job = make_job();
  job->job_id = pool.job_id++;
  job->op_code = OP_OPEN;
  job->payload.open.filename = filename;
  job->payload.open.flags = flags;
  job->payload.open.mode = mode;
  return job;
}

struct job *moonbitlang_async_make_stat_job(
  char *path,
  void *out,
  int follow_symlink
) {
  struct job *job = make_job();
  job->job_id = pool.job_id++;
  job->op_code = OP_STAT;
  job->payload.stat.path = path;
  job->payload.stat.out = out;
  job->payload.stat.follow_symlink = follow_symlink;
  return job;
}

struct job *moonbitlang_async_make_access_job(char *path, int amode) {
  struct job *job = make_job();
  job->job_id = pool.job_id++;
  job->op_code = OP_ACCESS;
  job->payload.access.path = path;
  job->payload.access.amode = amode;
  return job;
}

struct job *moonbitlang_async_make_remove_job(char *path) {
  struct job *job = make_job();
  job->job_id = pool.job_id++;
  job->op_code = OP_REMOVE;
  job->payload.remove.path = path;
  return job;
}

struct job *moonbitlang_async_make_mkdir_job(char *path, int mode) {
  struct job *job = make_job();
  job->job_id = pool.job_id++;
  job->op_code = OP_MKDIR;
  job->payload.mkdir.path = path;
  job->payload.mkdir.mode = mode;
  return job;
}

struct job *moonbitlang_async_make_rmdir_job(char *path) {
  struct job *job = make_job();
  job->job_id = pool.job_id++;
  job->op_code = OP_RMDIR;
  job->payload.rmdir.path = path;
  return job;
}

struct job *moonbitlang_async_make_readdir_job(DIR *dir, struct dirent **out) {
  struct job *job = make_job();
  job->job_id = pool.job_id++;
  job->op_code = OP_READDIR;
  job->payload.readdir.dir = dir;
  job->payload.readdir.out = out;
  return job;
}

struct job *moonbitlang_async_make_realpath_job(char *path, char **out) {
  struct job *job = make_job();
  job->job_id = pool.job_id++;
  job->op_code = OP_REALPATH;
  job->payload.realpath.path = path;
  job->payload.realpath.out = out;
  return job;
}

struct job *moonbitlang_async_make_spawn_job(
  char *path,
  char **args,
  char **envp,
  int stdin_fd,
  int stdout_fd,
  int stderr_fd,
  char *cwd
) {
  struct job *job = make_job();
  job->job_id = pool.job_id++;
  job->op_code = OP_SPAWN;
  job->payload.spawn.path = path;
  job->payload.spawn.args = args;
  job->payload.spawn.envp = envp;
  job->payload.spawn.stdio[0] = stdin_fd;
  job->payload.spawn.stdio[1] = stdout_fd;
  job->payload.spawn.stdio[2] = stderr_fd;
  job->payload.spawn.cwd = cwd;
  return job;
}

static
void free_addrinfo_ref(void *obj) {
  struct addrinfo *ai = *((struct addrinfo**)obj);
  if (ai) freeaddrinfo(ai);
}

struct addrinfo **moonbitlang_async_addrinfo_ref_make() {
  struct addrinfo **result = (struct addrinfo**)moonbit_make_external_object(
    free_addrinfo_ref,
    sizeof(struct addrinfo*)
  );
  *result = 0;
  return result;
}

struct addrinfo *moonbitlang_async_addrinfo_ref_get(struct addrinfo **ref) {
  struct addrinfo *result = *ref;
  *ref = 0;
  return result;
}

struct job *moonbitlang_async_make_getaddrinfo_job(
  char *hostname,
  struct addrinfo **out
) {
  struct job *job = make_job();
  job->job_id = pool.job_id++;
  job->op_code = OP_GETADDRINFO;
  job->payload.getaddrinfo.hostname = hostname;
  job->payload.getaddrinfo.out = out;
  return job;
}

int32_t moonbitlang_async_fetch_completion(int notify_recv) {
  int job_id;
  int32_t ret = read(notify_recv, &job_id, sizeof(int));
  if (ret < 0)
    return ret;

  return job_id;
}
