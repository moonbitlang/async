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
#include <signal.h>
#include <spawn.h>
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

struct spawn_result {
  int mode;
  pid_t pid;
  int pidfd;
  int error;
};

struct child_slot {
  pid_t pid;
  int pidfd;
  int iteration;
  int done;
};

static int xpidfd_open(pid_t pid, unsigned int flags) {
  return (int)syscall(SYS_pidfd_open, pid, flags);
}

static long now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1000000000L + ts.tv_nsec;
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
  if (spawn_method == 1 || spawn_method == 2) {
    struct spawn_result result = {
      .mode = mode,
      .pid = -1,
      .pidfd = -1,
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

static void close_child(struct child_slot *child) {
  if (child->done) {
    return;
  }
  child->done = 1;
  if (child->pid > 0) {
    kill(child->pid, SIGKILL);
    waitpid(child->pid, NULL, 0);
  }
  if (child->pidfd >= 0) {
    close(child->pidfd);
  }
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

  if (iterations <= 0 || parallelism <= 0) {
    fprintf(stderr, "iterations and parallelism must be positive\n");
    return 2;
  }

  printf(
    "pidfd epoll/waitid repro: iterations=%d mode=%d epollet=%d "
    "spawn_method=%d parallelism=%d pid=%ld\n",
    iterations,
    mode,
    use_epollet,
    spawn_method,
    parallelism,
    (long)getpid()
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
      int err = spawn_child(
        mode,
        spawn_method,
        &children[i].pid,
        &children[i].pidfd
      );
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
