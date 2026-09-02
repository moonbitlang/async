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

int main(int argc, char **argv) {
  self_path = argv[0];
  if (argc > 1 && strcmp(argv[1], "--child") == 0) {
    child_body(argc > 2 ? atoi(argv[2]) : 0);
  }

  int iterations = argc > 1 ? atoi(argv[1]) : 20000;
  int mode = argc > 2 ? atoi(argv[2]) : 0;
  int use_epollet = argc > 3 ? atoi(argv[3]) : 1;
  int spawn_method = argc > 4 ? atoi(argv[4]) : 0;

  if (iterations <= 0) {
    fprintf(stderr, "iterations must be positive\n");
    return 2;
  }

  printf(
    "pidfd epoll/waitid repro: iterations=%d mode=%d epollet=%d "
    "spawn_method=%d pid=%ld\n",
    iterations,
    mode,
    use_epollet,
    spawn_method,
    (long)getpid()
  );

  int spurious = 0;
  int eagain = 0;
  int wait_errors = 0;
  int epoll_timeouts = 0;

  for (int i = 0; i < iterations; i++) {
    pid_t pid;
    int pidfd;
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
        errno = err;
        perror("pthread_create spawn");
        return 1;
      }
      err = pthread_join(thread, NULL);
      if (err != 0) {
        errno = err;
        perror("pthread_join spawn");
        return 1;
      }
      if (result.error) {
        errno = result.error;
        perror("thread fork/pidfd_open");
        if (result.pid > 0) {
          kill(result.pid, SIGKILL);
          waitpid(result.pid, NULL, 0);
        }
        return 1;
      }
      pid = result.pid;
      pidfd = result.pidfd;
    } else {
      pid = fork();
      if (pid < 0) {
        perror("fork");
        return 1;
      }
      if (pid == 0) {
        child_body(mode);
      }

      pidfd = xpidfd_open(pid, 0);
      if (pidfd < 0) {
        perror("pidfd_open");
        kill(pid, SIGKILL);
        waitpid(pid, NULL, 0);
        return 1;
      }
    }

    // Match moonbitlang/async: pidfd_open(..., 0), then fcntl O_NONBLOCK in
    // event_bus_register.
    int flags = fcntl(pidfd, F_GETFL);
    if (flags >= 0 && !(flags & O_NONBLOCK)) {
      if (fcntl(pidfd, F_SETFL, flags | O_NONBLOCK) < 0) {
        perror("fcntl O_NONBLOCK");
        close(pidfd);
        kill(pid, SIGKILL);
        waitpid(pid, NULL, 0);
        return 1;
      }
    }

    int epfd = epoll_create1(EPOLL_CLOEXEC);
    if (epfd < 0) {
      perror("epoll_create1");
      close(pidfd);
      kill(pid, SIGKILL);
      waitpid(pid, NULL, 0);
      return 1;
    }

    struct epoll_event ev;
    memset(&ev, 0, sizeof ev);
    ev.events = EPOLLIN | EPOLLRDHUP | (use_epollet ? EPOLLET : 0);
    ev.data.u64 = ((uint64_t)(uint32_t)pidfd) |
      ((uint64_t)(uint32_t)(i + 1) << 32);
    if (epoll_ctl(epfd, EPOLL_CTL_ADD, pidfd, &ev) < 0) {
      perror("epoll_ctl ADD");
      close(epfd);
      close(pidfd);
      kill(pid, SIGKILL);
      waitpid(pid, NULL, 0);
      return 1;
    }

    if (mode == 2 || mode == 5) {
      // Give the child enough time to arm pause(), then hard-cancel it.
      usleep(10 + (i % 50));
      kill(pid, SIGKILL);
    }

    struct epoll_event out;
    memset(&out, 0, sizeof out);
    long start = now_ns();
    int n = epoll_wait(epfd, &out, 1, 5000);
    long waited_ns = now_ns() - start;
    if (n < 0) {
      perror("epoll_wait");
      close(epfd);
      close(pidfd);
      kill(pid, SIGKILL);
      waitpid(pid, NULL, 0);
      return 1;
    }
    if (n == 0) {
      epoll_timeouts++;
      fprintf(
        stderr,
        "TIMEOUT iter=%d pid=%ld pidfd=%d waited_ms=%.3f\n",
        i,
        (long)pid,
        pidfd,
        waited_ns / 1000000.0
      );
      close(epfd);
      close(pidfd);
      kill(pid, SIGKILL);
      waitpid(pid, NULL, 0);
      continue;
    }

    siginfo_t si;
    memset(&si, 0, sizeof si);
    errno = 0;
    int ret = waitid(P_PIDFD, pidfd, &si, WEXITED | WNOHANG);
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
        i,
        (long)pid,
        pidfd,
        out.events,
        ret,
        err,
        strerror(err),
        waited_ns / 1000000.0
      );
      kill(pid, SIGKILL);
      waitpid(pid, NULL, 0);
    } else if (si.si_pid == 0) {
      spurious++;
      fprintf(
        stderr,
        "SPURIOUS iter=%d pid=%ld pidfd=%d events=0x%x si_pid=0 "
        "si_code=%d si_status=%d waited_ms=%.3f\n",
        i,
        (long)pid,
        pidfd,
        out.events,
        si.si_code,
        si.si_status,
        waited_ns / 1000000.0
      );
      kill(pid, SIGKILL);
      waitpid(pid, NULL, 0);
    }

    close(epfd);
    close(pidfd);

    if ((i + 1) % 1000 == 0) {
      printf(
        "progress %d/%d spurious=%d eagain=%d wait_errors=%d timeouts=%d\n",
        i + 1,
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
