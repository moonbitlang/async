// Self-contained stress test for:
//   epoll_wait(pidfd readable) -> waitid(P_PIDFD, WEXITED | WNOHANG)
//
// A failure line means epoll reported readiness for the pidfd, but waitid
// returned success with si_pid == 0, or failed with EAGAIN.
//
// Build:
//   gcc -O2 -Wall -Wextra -pthread tools/pidfd_epoll_waitid_repro.c -o /tmp/pidfd_epoll_waitid_repro
//
// Run:
//   /tmp/pidfd_epoll_waitid_repro 20000 0 1 2

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <spawn.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef P_PIDFD
#define P_PIDFD 3
#endif

extern char **environ;

static const char *self_path;
static const char *external_child_path;

struct spawn_result {
  int mode;
  pid_t pid;
  int pidfd;
  int stdin_fd;
  int stdout_fd;
  int error;
};

struct child_slot {
  pid_t pid;
  int pidfd;
  int stdin_fd;
  int stdout_fd;
  int iteration;
  int done;
};

struct race_context {
  int epfd;
  int pidfd;
  atomic_int epoll_ret;
  atomic_int epoll_errno;
  atomic_int epoll_events;
  atomic_long epoll_ns;
  atomic_int epoll_probe_ret;
  atomic_int epoll_probe_errno;
  atomic_int epoll_probe_pid;
  atomic_int epoll_probe_code;
  atomic_int epoll_probe_status;
  atomic_long waitid_ns;
  atomic_int waitid_errno;
  atomic_int waitid_pid;
  atomic_int waitid_code;
  atomic_int waitid_status;
};

struct spin_waitid_context {
  int pidfd;
};

static int xpidfd_open(pid_t pid, unsigned int flags) {
  return (int)syscall(SYS_pidfd_open, pid, flags);
}

static long now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1000000000L + ts.tv_nsec;
}

static void close_if_open(int *fd) {
  if (*fd >= 0) {
    close(*fd);
    *fd = -1;
  }
}

static int write_all(int fd, const char *buf, size_t len) {
  while (len > 0) {
    ssize_t n = write(fd, buf, len);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      return errno;
    }
    buf += n;
    len -= (size_t)n;
  }
  return 0;
}

static void drain_fd(int fd) {
  char buf[4096];
  for (;;) {
    ssize_t n = read(fd, buf, sizeof buf);
    if (n > 0) {
      continue;
    }
    if (n < 0 && errno == EINTR) {
      continue;
    }
    break;
  }
}

static void *short_thread_main(void *arg) {
  (void)arg;
  usleep(1000 + (getpid() % 1000));
  return NULL;
}

static void *long_thread_main(void *arg) {
  (void)arg;
  usleep(1000000);
  return NULL;
}

static void child_body(int mode) {
  if (mode == 0) {
    _exit(0);
  }

  if (mode == 1) {
    usleep(100 + (getpid() % 200));
    _exit(0);
  }

  if (mode == 3) {
    pthread_t thread;
    if (pthread_create(&thread, NULL, short_thread_main, NULL) != 0) {
      _exit(111);
    }
    // Exercise the "thread-group leader exited, other threads still alive"
    // pidfd_poll case. This intentionally avoids exit_group().
    syscall(SYS_exit, 0);
  }

  if (mode == 6) {
    exit(0);
  }

  if (mode == 7) {
    for (int i = 0; i < 4; i++) {
      pthread_t thread;
      if (pthread_create(&thread, NULL, long_thread_main, NULL) != 0) {
        _exit(111);
      }
    }
    exit(0);
  }

  // Modes 2 and 5 are for the shell-output-limit shape: the parent will
  // SIGKILL us.
  for (;;) {
    pause();
  }
}

static void *spawn_in_thread_main(void *arg) {
  struct spawn_result *result = arg;
  pid_t pid = fork();
  if (pid < 0) {
    result->error = errno;
    return NULL;
  }
  if (pid == 0) {
    child_body(result->mode);
  }
  result->pid = pid;
  result->pidfd = xpidfd_open(pid, 0);
  if (result->pidfd < 0) {
    result->error = errno;
  }
  return NULL;
}

static void *posix_spawn_in_thread_main(void *arg) {
  struct spawn_result *result = arg;
  if (result->mode == 8) {
    if (!external_child_path) {
      result->error = EINVAL;
      return NULL;
    }

    int stdin_pipe[2] = { -1, -1 };
    int stdout_pipe[2] = { -1, -1 };
    if (pipe(stdin_pipe) < 0 || pipe(stdout_pipe) < 0) {
      result->error = errno;
      close_if_open(&stdin_pipe[0]);
      close_if_open(&stdin_pipe[1]);
      close_if_open(&stdout_pipe[0]);
      close_if_open(&stdout_pipe[1]);
      return NULL;
    }

    posix_spawn_file_actions_t file_actions;
    int err = posix_spawn_file_actions_init(&file_actions);
    if (err != 0) {
      result->error = err;
      close_if_open(&stdin_pipe[0]);
      close_if_open(&stdin_pipe[1]);
      close_if_open(&stdout_pipe[0]);
      close_if_open(&stdout_pipe[1]);
      return NULL;
    }

    err = posix_spawn_file_actions_adddup2(&file_actions, stdin_pipe[0], 0);
    if (err == 0) {
      err = posix_spawn_file_actions_adddup2(&file_actions, stdout_pipe[1], 1);
    }
    if (err == 0) {
      err = posix_spawn_file_actions_addclose(&file_actions, stdin_pipe[1]);
    }
    if (err == 0) {
      err = posix_spawn_file_actions_addclose(&file_actions, stdout_pipe[0]);
    }
    if (err != 0) {
      result->error = err;
      posix_spawn_file_actions_destroy(&file_actions);
      close_if_open(&stdin_pipe[0]);
      close_if_open(&stdin_pipe[1]);
      close_if_open(&stdout_pipe[0]);
      close_if_open(&stdout_pipe[1]);
      return NULL;
    }

    char *cat_argv[] = { (char *)external_child_path, NULL };
    pid_t pid = -1;
    err = posix_spawn(
      &pid,
      external_child_path,
      &file_actions,
      NULL,
      cat_argv,
      environ
    );
    posix_spawn_file_actions_destroy(&file_actions);
    if (err != 0) {
      result->error = err;
      close_if_open(&stdin_pipe[0]);
      close_if_open(&stdin_pipe[1]);
      close_if_open(&stdout_pipe[0]);
      close_if_open(&stdout_pipe[1]);
      return NULL;
    }

    close_if_open(&stdin_pipe[0]);
    close_if_open(&stdout_pipe[1]);
    result->pid = pid;
    result->stdin_fd = stdin_pipe[1];
    result->stdout_fd = stdout_pipe[0];
    result->pidfd = xpidfd_open(pid, 0);
    if (result->pidfd < 0) {
      result->error = errno;
    }
    return NULL;
  }

  char *true_argv[] = { (char *)"true", NULL };
  char *sleep_argv[] = { (char *)"sleep", (char *)"60", NULL };
  char *self_exit_argv[] = {
    (char *)self_path,
    (char *)"--child",
    (char *)"0",
    NULL,
  };
  char *self_sleep_argv[] = {
    (char *)self_path,
    (char *)"--child",
    (char *)"2",
    NULL,
  };
  char *self_asan_exit_argv[] = {
    (char *)self_path,
    (char *)"--child",
    (char *)"6",
    NULL,
  };
  char *self_asan_thread_exit_argv[] = {
    (char *)self_path,
    (char *)"--child",
    (char *)"7",
    NULL,
  };
  char **argv = result->mode == 4 ? self_exit_argv :
    result->mode == 5 ? self_sleep_argv :
    result->mode == 6 ? self_asan_exit_argv :
    result->mode == 7 ? self_asan_thread_exit_argv :
    result->mode == 2 ? sleep_argv :
    true_argv;
  const char *path = result->mode == 4 || result->mode == 5 ||
    result->mode == 6 || result->mode == 7 ? self_path :
    result->mode == 2 ? "/bin/sleep" :
    "/bin/true";

  pid_t pid = -1;
  int err = posix_spawn(&pid, path, NULL, NULL, argv, environ);
  if (err != 0) {
    result->error = err;
    return NULL;
  }
  result->pid = pid;
  result->pidfd = xpidfd_open(pid, 0);
  if (result->pidfd < 0) {
    result->error = errno;
  }
  return NULL;
}

static int spawn_child(int mode, int spawn_method, pid_t *pid, int *pidfd) {
  if (mode == 8) {
    return EINVAL;
  }

  if (spawn_method == 1 || spawn_method == 2) {
    struct spawn_result result = {
      .mode = mode,
      .pid = -1,
      .pidfd = -1,
      .stdin_fd = -1,
      .stdout_fd = -1,
      .error = 0,
    };
    pthread_t thread;
    int err = pthread_create(
      &thread,
      NULL,
      spawn_method == 1 ? spawn_in_thread_main : posix_spawn_in_thread_main,
      &result
    );
    if (err != 0) {
      return err;
    }
    err = pthread_join(thread, NULL);
    if (err != 0) {
      return err;
    }
    if (result.error) {
      if (result.pid > 0) {
        kill(result.pid, SIGKILL);
        waitpid(result.pid, NULL, 0);
      }
      close_if_open(&result.stdin_fd);
      close_if_open(&result.stdout_fd);
      return result.error;
    }
    *pid = result.pid;
    *pidfd = result.pidfd;
    return 0;
  }

  *pid = fork();
  if (*pid < 0) {
    return errno;
  }
  if (*pid == 0) {
    child_body(mode);
  }

  *pidfd = xpidfd_open(*pid, 0);
  if (*pidfd < 0) {
    int err = errno;
    kill(*pid, SIGKILL);
    waitpid(*pid, NULL, 0);
    return err;
  }
  return 0;
}

static int spawn_child_slot(int mode, int spawn_method, struct child_slot *child) {
  child->stdin_fd = -1;
  child->stdout_fd = -1;

  if (mode != 8) {
    return spawn_child(mode, spawn_method, &child->pid, &child->pidfd);
  }

  if (spawn_method != 2) {
    return EINVAL;
  }

  struct spawn_result result = {
    .mode = mode,
    .pid = -1,
    .pidfd = -1,
    .stdin_fd = -1,
    .stdout_fd = -1,
    .error = 0,
  };
  pthread_t thread;
  int err = pthread_create(&thread, NULL, posix_spawn_in_thread_main, &result);
  if (err != 0) {
    return err;
  }
  err = pthread_join(thread, NULL);
  if (err != 0) {
    return err;
  }
  if (result.error) {
    if (result.pid > 0) {
      kill(result.pid, SIGKILL);
      waitpid(result.pid, NULL, 0);
    }
    close_if_open(&result.stdin_fd);
    close_if_open(&result.stdout_fd);
    return result.error;
  }
  child->pid = result.pid;
  child->pidfd = result.pidfd;
  child->stdin_fd = result.stdin_fd;
  child->stdout_fd = result.stdout_fd;
  return 0;
}

static void close_child(struct child_slot *child) {
  if (child->done) {
    close_if_open(&child->stdin_fd);
    if (child->stdout_fd >= 0) {
      drain_fd(child->stdout_fd);
      close_if_open(&child->stdout_fd);
    }
    close_if_open(&child->pidfd);
    return;
  }
  child->done = 1;
  close_if_open(&child->stdin_fd);
  if (child->pid > 0) {
    kill(child->pid, SIGKILL);
    waitpid(child->pid, NULL, 0);
  }
  if (child->stdout_fd >= 0) {
    drain_fd(child->stdout_fd);
    close_if_open(&child->stdout_fd);
  }
  if (child->pidfd >= 0) {
    close_if_open(&child->pidfd);
  }
}

static void *race_epoll_thread_main(void *arg) {
  struct race_context *ctx = arg;
  struct epoll_event ev;
  memset(&ev, 0, sizeof ev);

  errno = 0;
  int ret = epoll_wait(ctx->epfd, &ev, 1, 5000);
  long observed_ns = now_ns();
  atomic_store(&ctx->epoll_ret, ret);
  atomic_store(&ctx->epoll_errno, errno);
  atomic_store(&ctx->epoll_events, ret > 0 ? (int)ev.events : 0);
  atomic_store(&ctx->epoll_ns, observed_ns);

  if (ret > 0) {
    siginfo_t si;
    memset(&si, 0, sizeof si);
    errno = 0;
    int wait_ret = waitid(
      P_PIDFD,
      ctx->pidfd,
      &si,
      WEXITED | WNOHANG | WNOWAIT
    );
    atomic_store(&ctx->epoll_probe_ret, wait_ret);
    atomic_store(&ctx->epoll_probe_errno, errno);
    atomic_store(&ctx->epoll_probe_pid, si.si_pid);
    atomic_store(&ctx->epoll_probe_code, si.si_code);
    atomic_store(&ctx->epoll_probe_status, si.si_status);
  }

  return NULL;
}

static void *race_waitid_thread_main(void *arg) {
  struct race_context *ctx = arg;

  for (;;) {
    siginfo_t si;
    memset(&si, 0, sizeof si);
    errno = 0;
    int ret = waitid(
      P_PIDFD,
      ctx->pidfd,
      &si,
      WEXITED | WNOHANG | WNOWAIT
    );
    if (ret < 0) {
      atomic_store(&ctx->waitid_errno, errno);
      atomic_store(&ctx->waitid_ns, now_ns());
      return NULL;
    }
    if (si.si_pid != 0) {
      atomic_store(&ctx->waitid_pid, si.si_pid);
      atomic_store(&ctx->waitid_code, si.si_code);
      atomic_store(&ctx->waitid_status, si.si_status);
      atomic_store(&ctx->waitid_ns, now_ns());
      return NULL;
    }
    sched_yield();
  }
}

static int run_two_thread_race(int iterations, int use_epollet) {
  int epoll_wins = 0;
  int waitid_wins = 0;
  int ties = 0;
  int epoll_probe_empty = 0;
  int epoll_timeouts = 0;
  int errors = 0;

  printf(
    "pidfd epoll/waitid two-thread race: iterations=%d epollet=%d pid=%ld\n",
    iterations,
    use_epollet,
    (long)getpid()
  );

  for (int i = 0; i < iterations; i++) {
    struct child_slot child = {
      .pid = -1,
      .pidfd = -1,
      .stdin_fd = -1,
      .stdout_fd = -1,
      .iteration = i,
      .done = 0,
    };

    int err = spawn_child_slot(2, 0, &child);
    if (err != 0) {
      errno = err;
      perror("spawn_child_slot race");
      errors++;
      close_child(&child);
      continue;
    }

    int epfd = epoll_create1(EPOLL_CLOEXEC);
    if (epfd < 0) {
      perror("epoll_create1 race");
      errors++;
      close_child(&child);
      continue;
    }

    int flags = fcntl(child.pidfd, F_GETFL);
    if (flags >= 0 && !(flags & O_NONBLOCK)) {
      if (fcntl(child.pidfd, F_SETFL, flags | O_NONBLOCK) < 0) {
        perror("fcntl race O_NONBLOCK");
        errors++;
        close(epfd);
        close_child(&child);
        continue;
      }
    }

    struct epoll_event ev;
    memset(&ev, 0, sizeof ev);
    ev.events = EPOLLIN | EPOLLRDHUP | (use_epollet ? EPOLLET : 0);
    ev.data.fd = child.pidfd;
    if (epoll_ctl(epfd, EPOLL_CTL_ADD, child.pidfd, &ev) < 0) {
      perror("epoll_ctl race");
      errors++;
      close(epfd);
      close_child(&child);
      continue;
    }

    struct race_context ctx;
    memset(&ctx, 0, sizeof ctx);
    ctx.epfd = epfd;
    ctx.pidfd = child.pidfd;

    pthread_t epoll_thread;
    pthread_t waitid_thread;
    int epoll_thread_started = 0;
    int waitid_thread_started = 0;
    err = pthread_create(&epoll_thread, NULL, race_epoll_thread_main, &ctx);
    if (err == 0) {
      epoll_thread_started = 1;
    }
    if (err == 0) {
      err = pthread_create(&waitid_thread, NULL, race_waitid_thread_main, &ctx);
      if (err == 0) {
        waitid_thread_started = 1;
      }
    }
    if (err != 0) {
      errno = err;
      perror("pthread_create race");
      errors++;
      kill(child.pid, SIGKILL);
      waitpid(child.pid, NULL, 0);
      child.done = 1;
      if (epoll_thread_started) {
        pthread_join(epoll_thread, NULL);
      }
      if (waitid_thread_started) {
        pthread_join(waitid_thread, NULL);
      }
      close(epfd);
      close_child(&child);
      continue;
    }

    usleep(100);
    kill(child.pid, SIGKILL);

    pthread_join(epoll_thread, NULL);
    pthread_join(waitid_thread, NULL);

    long epoll_ns = atomic_load(&ctx.epoll_ns);
    long waitid_ns = atomic_load(&ctx.waitid_ns);
    int epoll_ret = atomic_load(&ctx.epoll_ret);
    int epoll_errno = atomic_load(&ctx.epoll_errno);
    int waitid_errno = atomic_load(&ctx.waitid_errno);
    int probe_pid = atomic_load(&ctx.epoll_probe_pid);

    if (epoll_ret == 0) {
      epoll_timeouts++;
      fprintf(
        stderr,
        "RACE_TIMEOUT iter=%d pid=%ld pidfd=%d waitid_pid=%d waitid_errno=%d\n",
        i,
        (long)child.pid,
        child.pidfd,
        atomic_load(&ctx.waitid_pid),
        waitid_errno
      );
    } else if (epoll_ret < 0 || waitid_errno != 0) {
      errors++;
      fprintf(
        stderr,
        "RACE_ERROR iter=%d pid=%ld pidfd=%d epoll_ret=%d "
        "epoll_errno=%d(%s) waitid_errno=%d(%s)\n",
        i,
        (long)child.pid,
        child.pidfd,
        epoll_ret,
        epoll_errno,
        strerror(epoll_errno),
        waitid_errno,
        strerror(waitid_errno)
      );
    } else if (probe_pid == 0) {
      epoll_probe_empty++;
      fprintf(
        stderr,
        "RACE_EPOLL_PROBE_EMPTY iter=%d pid=%ld pidfd=%d events=0x%x "
        "epoll_ns=%ld waitid_ns=%ld waitid_pid=%d waitid_code=%d "
        "waitid_status=%d\n",
        i,
        (long)child.pid,
        child.pidfd,
        atomic_load(&ctx.epoll_events),
        epoll_ns,
        waitid_ns,
        atomic_load(&ctx.waitid_pid),
        atomic_load(&ctx.waitid_code),
        atomic_load(&ctx.waitid_status)
      );
    }

    if (epoll_ns < waitid_ns) {
      epoll_wins++;
    } else if (waitid_ns < epoll_ns) {
      waitid_wins++;
    } else {
      ties++;
    }

    siginfo_t si;
    memset(&si, 0, sizeof si);
    waitid(P_PIDFD, child.pidfd, &si, WEXITED);
    child.done = 1;
    close(epfd);
    close_child(&child);

    if ((i + 1) % 1000 == 0 || i + 1 == iterations) {
      printf(
        "race progress %d/%d epoll_wins=%d waitid_wins=%d ties=%d "
        "probe_empty=%d timeouts=%d errors=%d\n",
        i + 1,
        iterations,
        epoll_wins,
        waitid_wins,
        ties,
        epoll_probe_empty,
        epoll_timeouts,
        errors
      );
      fflush(stdout);
    }
  }

  printf(
    "race done iterations=%d epoll_wins=%d waitid_wins=%d ties=%d "
    "probe_empty=%d timeouts=%d errors=%d\n",
    iterations,
    epoll_wins,
    waitid_wins,
    ties,
    epoll_probe_empty,
    epoll_timeouts,
    errors
  );

  return (epoll_timeouts || errors) ? 1 : 0;
}

static void *spin_waitid_thread_main(void *arg) {
  struct spin_waitid_context *ctx = arg;

  for (;;) {
    siginfo_t si;
    memset(&si, 0, sizeof si);
    errno = 0;
    int ret = waitid(
      P_PIDFD,
      ctx->pidfd,
      &si,
      WEXITED | WNOHANG | WNOWAIT
    );
    if (ret < 0) {
      return (void *)(intptr_t)(errno ? errno : EIO);
    }
    if (si.si_pid != 0) {
      return NULL;
    }
  }
}

static int run_spin_waitid_after_epoll(
  int iterations,
  int use_epollet,
  int spawn_method,
  int child_mode
) {
  int ready = 0;
  int empty = 0;
  int eagain = 0;
  int wait_errors = 0;
  int spinner_errors = 0;
  int epoll_timeouts = 0;
  int errors = 0;

  printf(
    "pidfd epoll plus spinning waitid repro: iterations=%d epollet=%d "
    "spawn_method=%d child_mode=%d pid=%ld external_child=%s\n",
    iterations,
    use_epollet,
    spawn_method,
    child_mode,
    (long)getpid(),
    external_child_path ? external_child_path : "(none)"
  );

  for (int i = 0; i < iterations; i++) {
    struct child_slot child = {
      .pid = -1,
      .pidfd = -1,
      .stdin_fd = -1,
      .stdout_fd = -1,
      .iteration = i,
      .done = 0,
    };

    int err = spawn_child_slot(child_mode, spawn_method, &child);
    if (err != 0) {
      errno = err;
      perror("spawn_child_slot spin");
      errors++;
      close_child(&child);
      continue;
    }

    int epfd = epoll_create1(EPOLL_CLOEXEC);
    if (epfd < 0) {
      perror("epoll_create1 spin");
      errors++;
      close_child(&child);
      continue;
    }

    int flags = fcntl(child.pidfd, F_GETFL);
    if (flags >= 0 && !(flags & O_NONBLOCK)) {
      if (fcntl(child.pidfd, F_SETFL, flags | O_NONBLOCK) < 0) {
        perror("fcntl spin O_NONBLOCK");
        errors++;
        close(epfd);
        close_child(&child);
        continue;
      }
    }

    struct epoll_event ev;
    memset(&ev, 0, sizeof ev);
    ev.events = EPOLLIN | EPOLLRDHUP | (use_epollet ? EPOLLET : 0);
    ev.data.fd = child.pidfd;
    if (epoll_ctl(epfd, EPOLL_CTL_ADD, child.pidfd, &ev) < 0) {
      perror("epoll_ctl spin");
      errors++;
      close(epfd);
      close_child(&child);
      continue;
    }

    struct spin_waitid_context ctx = { .pidfd = child.pidfd };
    pthread_t spinner;
    err = pthread_create(&spinner, NULL, spin_waitid_thread_main, &ctx);
    if (err != 0) {
      errno = err;
      perror("pthread_create spin");
      errors++;
      close(epfd);
      close_child(&child);
      continue;
    }

    if (child_mode == 8) {
      static const char payload[] = "alpha\nbeta\ngamma";
      err = write_all(child.stdin_fd, payload, sizeof(payload) - 1);
      if (err != 0) {
        errno = err;
        perror("write spin external child stdin");
        errors++;
        kill(child.pid, SIGKILL);
      }
      close_if_open(&child.stdin_fd);
    } else if (child_mode == 2 || child_mode == 5) {
      usleep(100);
      kill(child.pid, SIGKILL);
    }

    struct epoll_event event;
    memset(&event, 0, sizeof event);
    errno = 0;
    int epoll_ret = epoll_wait(epfd, &event, 1, 5000);
    int epoll_errno = errno;

    siginfo_t si;
    memset(&si, 0, sizeof si);
    errno = 0;
    int wait_ret = -1;
    int wait_errno = 0;
    if (epoll_ret > 0) {
      wait_ret = waitid(P_PIDFD, child.pidfd, &si, WEXITED | WNOHANG);
      wait_errno = errno;
    }

    int outcome = 0;
    if (epoll_ret < 0) {
      wait_errors++;
      outcome = 1;
    } else if (epoll_ret == 0) {
      epoll_timeouts++;
      outcome = 2;
    } else if (wait_ret < 0) {
      wait_errors++;
      if (wait_errno == EAGAIN) {
        eagain++;
      }
      outcome = 3;
    } else if (si.si_pid == 0) {
      empty++;
      outcome = 4;
    } else {
      ready++;
      child.done = 1;
      outcome = 5;
    }

    void *spinner_result = NULL;
    pthread_join(spinner, &spinner_result);
    int spinner_errno = (int)(intptr_t)spinner_result;

    if (outcome == 1) {
      fprintf(
        stderr,
        "SPIN_EPOLL_ERROR iter=%d pid=%ld pidfd=%d errno=%d(%s)\n",
        i,
        (long)child.pid,
        child.pidfd,
        epoll_errno,
        strerror(epoll_errno)
      );
    } else if (outcome == 2) {
      fprintf(
        stderr,
        "SPIN_TIMEOUT iter=%d pid=%ld pidfd=%d spinner_errno=%d(%s)\n",
        i,
        (long)child.pid,
        child.pidfd,
        spinner_errno,
        strerror(spinner_errno)
      );
    } else if (outcome == 3) {
      fprintf(
        stderr,
        "SPIN_WAIT_ERROR iter=%d pid=%ld pidfd=%d events=0x%x ret=%d "
        "errno=%d(%s) spinner_errno=%d(%s)\n",
        i,
        (long)child.pid,
        child.pidfd,
        event.events,
        wait_ret,
        wait_errno,
        strerror(wait_errno),
        spinner_errno,
        strerror(spinner_errno)
      );
    } else if (outcome == 4) {
      fprintf(
        stderr,
        "SPIN_EMPTY_AFTER_EPOLL iter=%d pid=%ld pidfd=%d events=0x%x "
        "si_code=%d si_status=%d spinner_errno=%d(%s)\n",
        i,
        (long)child.pid,
        child.pidfd,
        event.events,
        si.si_code,
        si.si_status,
        spinner_errno,
        strerror(spinner_errno)
      );
    }

    if (spinner_errno != 0 && !(child.done && spinner_errno == ECHILD)) {
      spinner_errors++;
    }

    if (!child.done) {
      waitid(P_PIDFD, child.pidfd, &si, WEXITED);
      child.done = 1;
    }
    close(epfd);
    close_child(&child);

    if ((i + 1) % 1000 == 0 || i + 1 == iterations) {
      printf(
        "spin progress %d/%d ready=%d empty=%d eagain=%d wait_errors=%d "
        "spinner_errors=%d timeouts=%d errors=%d\n",
        i + 1,
        iterations,
        ready,
        empty,
        eagain,
        wait_errors,
        spinner_errors,
        epoll_timeouts,
        errors
      );
      fflush(stdout);
    }
  }

  printf(
    "spin done iterations=%d ready=%d empty=%d eagain=%d wait_errors=%d "
    "spinner_errors=%d timeouts=%d errors=%d\n",
    iterations,
    ready,
    empty,
    eagain,
    wait_errors,
    spinner_errors,
    epoll_timeouts,
    errors
  );

  return (
    empty ||
    eagain ||
    wait_errors ||
    spinner_errors ||
    epoll_timeouts ||
    errors
  ) ? 1 : 0;
}

int main(int argc, char **argv) {
  self_path = argv[0];
  if (argc > 1 && strcmp(argv[1], "--child") == 0) {
    child_body(argc > 2 ? atoi(argv[2]) : 0);
  }

  int iterations = argc > 1 ? atoi(argv[1]) : 20000;
  int mode = argc > 2 ? atoi(argv[2]) : 0;
  int use_epollet = argc > 3 ? atoi(argv[3]) : 1;
  int spawn_method = argc > 4 ? atoi(argv[4]) : 0;
  int parallelism = argc > 5 ? atoi(argv[5]) : 1;
  int spin_child_mode = argc > 6 ? atoi(argv[6]) : 0;
  external_child_path = mode == 10 ? (argc > 7 ? argv[7] : NULL) :
    (argc > 6 ? argv[6] : NULL);

  if (iterations <= 0 || parallelism <= 0) {
    fprintf(stderr, "iterations and parallelism must be positive\n");
    return 2;
  }

  if (mode == 8 && !external_child_path) {
    fprintf(stderr, "mode 8 requires external child path argument\n");
    return 2;
  }

  if (mode == 10 && spin_child_mode == 8 && !external_child_path) {
    fprintf(stderr, "mode 10 child_mode 8 requires external child path argument\n");
    return 2;
  }

  if (mode == 9) {
    return run_two_thread_race(iterations, use_epollet);
  }

  if (mode == 10) {
    return run_spin_waitid_after_epoll(
      iterations,
      use_epollet,
      spawn_method,
      spin_child_mode
    );
  }

  printf(
    "pidfd epoll/waitid repro: iterations=%d mode=%d epollet=%d "
    "spawn_method=%d parallelism=%d pid=%ld external_child=%s\n",
    iterations,
    mode,
    use_epollet,
    spawn_method,
    parallelism,
    (long)getpid(),
    external_child_path ? external_child_path : "(none)"
  );

  int spurious = 0;
  int eagain = 0;
  int wait_errors = 0;
  int epoll_timeouts = 0;

  for (int first = 0; first < iterations; first += parallelism) {
    int batch = iterations - first;
    if (batch > parallelism) {
      batch = parallelism;
    }

    struct child_slot *children = calloc(batch, sizeof(struct child_slot));
    struct epoll_event *events = calloc(batch, sizeof(struct epoll_event));
    if (!children || !events) {
      perror("calloc");
      free(children);
      free(events);
      return 1;
    }
    for (int i = 0; i < batch; i++) {
      children[i].pid = -1;
      children[i].pidfd = -1;
      children[i].stdin_fd = -1;
      children[i].stdout_fd = -1;
      children[i].iteration = first + i;
    }

    int epfd = epoll_create1(EPOLL_CLOEXEC);
    if (epfd < 0) {
      perror("epoll_create1");
      free(children);
      free(events);
      return 1;
    }

    for (int i = 0; i < batch; i++) {
      int err = spawn_child_slot(mode, spawn_method, &children[i]);
      if (err != 0) {
        errno = err;
        perror("spawn_child");
        for (int j = 0; j <= i; j++) {
          close_child(&children[j]);
        }
        close(epfd);
        free(children);
        free(events);
        return 1;
      }

      // Match moonbitlang/async: pidfd_open(..., 0), then fcntl O_NONBLOCK in
      // event_bus_register.
      int flags = fcntl(children[i].pidfd, F_GETFL);
      if (flags >= 0 && !(flags & O_NONBLOCK)) {
        if (fcntl(children[i].pidfd, F_SETFL, flags | O_NONBLOCK) < 0) {
          perror("fcntl O_NONBLOCK");
          for (int j = 0; j <= i; j++) {
            close_child(&children[j]);
          }
          close(epfd);
          free(children);
          free(events);
          return 1;
        }
      }

      struct epoll_event ev;
      memset(&ev, 0, sizeof ev);
      ev.events = EPOLLIN | EPOLLRDHUP | (use_epollet ? EPOLLET : 0);
      ev.data.u64 = ((uint64_t)(uint32_t)children[i].pidfd) |
        ((uint64_t)(uint32_t)(children[i].iteration + 1) << 32);
      if (epoll_ctl(epfd, EPOLL_CTL_ADD, children[i].pidfd, &ev) < 0) {
        perror("epoll_ctl ADD");
        for (int j = 0; j <= i; j++) {
          close_child(&children[j]);
        }
        close(epfd);
        free(children);
        free(events);
        return 1;
      }

      if (mode == 8) {
        static const char payload[] = "alpha\nbeta\ngamma";
        err = write_all(children[i].stdin_fd, payload, sizeof(payload) - 1);
        if (err != 0) {
          errno = err;
          perror("write external child stdin");
          for (int j = 0; j <= i; j++) {
            close_child(&children[j]);
          }
          close(epfd);
          free(children);
          free(events);
          return 1;
        }
        close_if_open(&children[i].stdin_fd);
      }
    }

    if (mode == 2 || mode == 5) {
      // Give all children enough time to arm pause(), then hard-cancel them.
      usleep(50);
      for (int i = 0; i < batch; i++) {
        kill(children[i].pid, SIGKILL);
      }
    }

    int remaining = batch;
    while (remaining > 0) {
      long start = now_ns();
      int n = epoll_wait(epfd, events, batch, 5000);
      long waited_ns = now_ns() - start;
      if (n < 0) {
        perror("epoll_wait");
        for (int i = 0; i < batch; i++) {
          close_child(&children[i]);
        }
        close(epfd);
        free(children);
        free(events);
        return 1;
      }
      if (n == 0) {
        epoll_timeouts += remaining;
        for (int i = 0; i < batch; i++) {
          if (!children[i].done) {
            fprintf(
              stderr,
              "TIMEOUT iter=%d pid=%ld pidfd=%d waited_ms=%.3f\n",
              children[i].iteration,
              (long)children[i].pid,
              children[i].pidfd,
              waited_ns / 1000000.0
            );
            close_child(&children[i]);
          }
        }
        break;
      }

      for (int i = 0; i < n; i++) {
        int iter = (int)(events[i].data.u64 >> 32) - 1;
        int child_index = iter - first;
        if (child_index < 0 || child_index >= batch) {
          fprintf(
            stderr,
            "UNKNOWN_EVENT iter=%d events=0x%x data=0x%llx\n",
            iter,
            events[i].events,
            (unsigned long long)events[i].data.u64
          );
          continue;
        }

        struct child_slot *child = &children[child_index];
        if (child->done) {
          continue;
        }

        siginfo_t si;
        memset(&si, 0, sizeof si);
        errno = 0;
        int ret = waitid(P_PIDFD, child->pidfd, &si, WEXITED | WNOHANG);
        int err = errno;
        if (ret < 0) {
          wait_errors++;
          if (err == EAGAIN) {
            eagain++;
          }
          fprintf(
            stderr,
            "WAIT_ERROR iter=%d pid=%ld pidfd=%d events=0x%x ret=%d "
            "errno=%d(%s) waited_ms=%.3f\n",
            child->iteration,
            (long)child->pid,
            child->pidfd,
            events[i].events,
            ret,
            err,
            strerror(err),
            waited_ns / 1000000.0
          );
          close_child(child);
          remaining--;
        } else if (si.si_pid == 0) {
          spurious++;
          fprintf(
            stderr,
            "SPURIOUS iter=%d pid=%ld pidfd=%d events=0x%x si_pid=0 "
            "si_code=%d si_status=%d waited_ms=%.3f\n",
            child->iteration,
            (long)child->pid,
            child->pidfd,
            events[i].events,
            si.si_code,
            si.si_status,
            waited_ns / 1000000.0
          );
          close_child(child);
          remaining--;
        } else {
          child->done = 1;
          close(child->pidfd);
          child->pidfd = -1;
          remaining--;
        }
      }
    }

    close(epfd);
    for (int i = 0; i < batch; i++) {
      close_child(&children[i]);
    }
    free(children);
    free(events);

    if ((first + batch) % 1000 == 0 || first + batch == iterations) {
      printf(
        "progress %d/%d spurious=%d eagain=%d wait_errors=%d timeouts=%d\n",
        first + batch,
        iterations,
        spurious,
        eagain,
        wait_errors,
        epoll_timeouts
      );
      fflush(stdout);
    }
  }

  printf(
    "done iterations=%d spurious=%d eagain=%d wait_errors=%d timeouts=%d\n",
    iterations,
    spurious,
    eagain,
    wait_errors,
    epoll_timeouts
  );

  return (spurious || eagain || wait_errors || epoll_timeouts) ? 1 : 0;
}
