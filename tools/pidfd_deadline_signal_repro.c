// pidfd readiness repro using an absolute child-exit deadline.
//
// The parent gives the child an absolute CLOCK_MONOTONIC deadline.  The child
// sleeps until that deadline and exits.  The parent sleeps until the same
// deadline plus a configurable offset, sends SIGKILL, waits for pidfd readiness
// with epoll, and immediately probes waitid(P_PIDFD, WNOHANG).
//
// Build:
//   gcc -O0 -Wall -Wextra tools/pidfd_deadline_signal_repro.c -o /tmp/pidfd_deadline_signal_repro
//
// Usage:
//   pidfd_deadline_signal_repro [iterations] [child-path] [deadline-lead-us] [kill-offset-us] [max-logs]

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
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

static int xpidfd_open(pid_t pid) {
  return (int)syscall(SYS_pidfd_open, pid, 0);
}

static void add_us(struct timespec *ts, long long us) {
  long long nsec = (long long)ts->tv_nsec + us * 1000LL;
  ts->tv_sec += nsec / 1000000000LL;
  nsec %= 1000000000LL;
  if (nsec < 0) {
    nsec += 1000000000LL;
    ts->tv_sec--;
  }
  ts->tv_nsec = (long)nsec;
}

static int sleep_until(struct timespec deadline) {
  for (;;) {
    int ret = clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &deadline, NULL);
    if (ret == 0) {
      return 0;
    }
    if (ret != EINTR) {
      errno = ret;
      return -1;
    }
  }
}

static int set_nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0) {
    return errno;
  }
  if ((flags & O_NONBLOCK) == 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
    return errno;
  }
  return 0;
}

static int set_blocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0) {
    return errno;
  }
  if ((flags & O_NONBLOCK) != 0 && fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) < 0) {
    return errno;
  }
  return 0;
}

static int add_epoll_fd(int epfd, int fd) {
  struct epoll_event event;
  memset(&event, 0, sizeof(event));
  event.events = EPOLLIN | EPOLLET | EPOLLRDHUP;
  event.data.fd = fd;
  if (epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &event) < 0) {
    return errno;
  }
  return 0;
}

static void close_if_open(int *fd) {
  if (*fd >= 0) {
    close(*fd);
    *fd = -1;
  }
}

static int waitid_pidfd_nohang(int pidfd, siginfo_t *si) {
  memset(si, 0, sizeof(*si));
  errno = 0;
  return waitid(P_PIDFD, pidfd, si, WEXITED | WNOHANG);
}

static int waitid_pidfd_blocking(int pidfd, siginfo_t *si) {
  memset(si, 0, sizeof(*si));
  errno = 0;
  return waitid(P_PIDFD, pidfd, si, WEXITED);
}

static int spawn_deadline_child(
  const char *child_path,
  struct timespec deadline,
  pid_t *pid
) {
  char sec_buf[32];
  char nsec_buf[32];
  snprintf(sec_buf, sizeof(sec_buf), "%lld", (long long)deadline.tv_sec);
  snprintf(nsec_buf, sizeof(nsec_buf), "%ld", deadline.tv_nsec);
  char *argv[] = { (char *)child_path, sec_buf, nsec_buf, NULL };
  return posix_spawn(pid, child_path, NULL, NULL, argv, environ);
}

static void print_empty_diagnostic(
  int iteration,
  pid_t pid,
  int pidfd,
  uint32_t events,
  long long kill_offset_us
) {
  siginfo_t by_pid;
  memset(&by_pid, 0, sizeof(by_pid));
  errno = 0;
  int by_pid_ret = waitid(P_PID, pid, &by_pid, WEXITED | WNOHANG | WNOWAIT);
  int by_pid_errno = errno;

  struct pollfd pfd = {
    .fd = pidfd,
    .events = POLLIN,
    .revents = 0,
  };
  errno = 0;
  int poll_ret = poll(&pfd, 1, 0);
  int poll_errno = errno;

  errno = 0;
  int kill0_ret = kill(pid, 0);
  int kill0_errno = errno;

  fprintf(
    stderr,
    "EMPTY_AFTER_EPOLL iteration=%d pid=%d pidfd=%d offset_us=%lld epoll_events=0x%x "
    "waitid(P_PID,WNOWAIT) ret=%d errno=%d si_pid=%d si_code=%d si_status=%d "
    "poll(pidfd) ret=%d errno=%d revents=0x%x kill(pid,0) ret=%d errno=%d\n",
    iteration,
    pid,
    pidfd,
    kill_offset_us,
    events,
    by_pid_ret,
    by_pid_errno,
    by_pid.si_pid,
    by_pid.si_code,
    by_pid.si_status,
    poll_ret,
    poll_errno,
    pfd.revents,
    kill0_ret,
    kill0_errno
  );
}

int main(int argc, char **argv) {
  int iterations = argc > 1 ? atoi(argv[1]) : 1000;
  const char *child_path = argc > 2 ? argv[2] : "/tmp/pidfd_deadline_exit_child";
  long long deadline_lead_us = argc > 3 ? strtoll(argv[3], NULL, 10) : 10000;
  long long kill_offset_us = argc > 4 ? strtoll(argv[4], NULL, 10) : 0;
  int max_logs = argc > 5 ? atoi(argv[5]) : 0;

  if (iterations <= 0 || deadline_lead_us < 0 || max_logs < 0) {
    fprintf(
      stderr,
      "usage: %s [iterations] [child-path] [deadline-lead-us>=0] [kill-offset-us] [max-logs]\n",
      argv[0]
    );
    return 2;
  }

  int killed = 0;
  int kill_esrch = 0;
  int pre_kill_probe_reaped = 0;
  int reaped_after_epoll = 0;
  int empty_after_epoll = 0;
  int epoll_timeouts = 0;
  int errors = 0;

  printf(
    "pidfd deadline signal repro: iterations=%d child=%s deadline_lead_us=%lld "
    "kill_offset_us=%lld pid=%ld\n",
    iterations,
    child_path,
    deadline_lead_us,
    kill_offset_us,
    (long)getpid()
  );

  for (int i = 0; i < iterations; i++) {
    pid_t pid = -1;
    int pidfd = -1;
    int epfd = -1;
    int child_reaped = 0;
    struct timespec deadline;
    if (clock_gettime(CLOCK_MONOTONIC, &deadline) < 0) {
      perror("clock_gettime");
      errors++;
      break;
    }
    add_us(&deadline, deadline_lead_us);

    int err = spawn_deadline_child(child_path, deadline, &pid);
    if (err != 0) {
      errno = err;
      perror("posix_spawn deadline child");
      errors++;
      goto cleanup;
    }

    pidfd = xpidfd_open(pid);
    if (pidfd < 0) {
      perror("pidfd_open");
      errors++;
      goto cleanup;
    }

    err = set_nonblocking(pidfd);
    if (err != 0) {
      errno = err;
      perror("fcntl pidfd O_NONBLOCK");
      errors++;
      goto cleanup;
    }

    epfd = epoll_create1(EPOLL_CLOEXEC);
    if (epfd < 0) {
      perror("epoll_create1");
      errors++;
      goto cleanup;
    }

    err = add_epoll_fd(epfd, pidfd);
    if (err != 0) {
      errno = err;
      perror("epoll_ctl ADD pidfd");
      errors++;
      goto cleanup;
    }

    err = set_blocking(pidfd);
    if (err != 0) {
      errno = err;
      perror("fcntl pidfd blocking");
      errors++;
      goto cleanup;
    }

    struct timespec kill_deadline = deadline;
    add_us(&kill_deadline, kill_offset_us);
    if (sleep_until(kill_deadline) < 0) {
      perror("clock_nanosleep parent");
      errors++;
      goto cleanup;
    }

    siginfo_t pre_kill_si;
    int pre_kill_wait_ret = waitid_pidfd_nohang(pidfd, &pre_kill_si);
    if (pre_kill_wait_ret < 0) {
      perror("pre-kill waitid(P_PIDFD)");
      errors++;
      goto cleanup;
    }
    if (pre_kill_si.si_pid != 0) {
      pre_kill_probe_reaped++;
      child_reaped = 1;
      goto cleanup;
    }

    errno = 0;
    int kill_ret = kill(pid, SIGKILL);
    int kill_errno = errno;
    if (kill_ret < 0 && kill_errno == ESRCH) {
      kill_esrch++;
    } else if (kill_ret < 0) {
      errno = kill_errno;
      perror("kill SIGKILL");
      errors++;
      goto cleanup;
    } else {
      killed++;
    }

    for (;;) {
      struct epoll_event event;
      memset(&event, 0, sizeof(event));
      int ret = epoll_wait(epfd, &event, 1, 5000);
      if (ret < 0) {
        if (errno == EINTR) {
          continue;
        }
        perror("epoll_wait pidfd");
        errors++;
        goto cleanup;
      }
      if (ret == 0) {
        epoll_timeouts++;
        goto cleanup;
      }
      if (event.data.fd != pidfd) {
        continue;
      }

      siginfo_t si;
      int wait_ret = waitid_pidfd_nohang(pidfd, &si);
      int saved_errno = errno;
      if (wait_ret < 0) {
        errno = saved_errno;
        perror("post-epoll waitid(P_PIDFD)");
        errors++;
        goto cleanup;
      }
      if (si.si_pid == 0) {
        empty_after_epoll++;
        if (empty_after_epoll <= max_logs) {
          print_empty_diagnostic(i, pid, pidfd, event.events, kill_offset_us);
        }
        siginfo_t blocking_si;
        int blocking_ret = waitid_pidfd_blocking(pidfd, &blocking_si);
        if (blocking_ret < 0) {
          perror("blocking waitid after empty");
          errors++;
        } else {
          child_reaped = 1;
        }
        goto cleanup;
      }

      reaped_after_epoll++;
      child_reaped = 1;
      goto cleanup;
    }

cleanup:
    if (pid > 0 && !child_reaped) {
      kill(pid, SIGKILL);
      waitpid(pid, NULL, 0);
    }
    close_if_open(&pidfd);
    close_if_open(&epfd);

    if ((i + 1) % 1000 == 0 || i + 1 == iterations) {
      printf(
        "progress %d/%d killed=%d kill_esrch=%d pre_kill_probe_reaped=%d reaped_after_epoll=%d "
        "empty_after_epoll=%d epoll_timeouts=%d errors=%d\n",
        i + 1,
        iterations,
        killed,
        kill_esrch,
        pre_kill_probe_reaped,
        reaped_after_epoll,
        empty_after_epoll,
        epoll_timeouts,
        errors
      );
    }
  }

  printf(
    "done killed=%d kill_esrch=%d pre_kill_probe_reaped=%d reaped_after_epoll=%d "
    "empty_after_epoll=%d epoll_timeouts=%d errors=%d\n",
    killed,
    kill_esrch,
    pre_kill_probe_reaped,
    reaped_after_epoll,
    empty_after_epoll,
    epoll_timeouts,
    errors
  );

  if (errors != 0) {
    return 1;
  }
  return empty_after_epoll == 0 ? 0 : 100;
}
