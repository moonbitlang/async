// Minimal pidfd/SIGKILL timing repro for the shell line-limit failure shape.
//
// Build:
//   gcc -O2 -Wall -Wextra tools/pidfd_sigkill_line_limit_repro.c -o /tmp/pidfd_sigkill_line_limit_repro
//
// Run:
//   /tmp/pidfd_sigkill_line_limit_repro 10000 /tmp/pidfd_repro_cat_asan 1000 20 4096
//
// This intentionally uses one child at a time.  The sequence is:
//   spawn cat with stdin/stdout pipes
//   register pidfd in epoll
//   write a long unterminated line
//   read enough stdout to "exceed the line limit", then close stdout reader
//   close stdin, so cat can also start natural EOF shutdown
//   probe waitid(P_PIDFD, WNOHANG), expecting not-ready
//   send SIGKILL
//   wait for pidfd EPOLLIN
//   immediately call waitid(P_PIDFD, WNOHANG)

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <spawn.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef P_PIDFD
#define P_PIDFD 3
#endif

extern char **environ;

static int xpidfd_open(pid_t pid) {
  return (int)syscall(SYS_pidfd_open, pid, 0);
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

static int spawn_cat(
  const char *cat_path,
  pid_t *pid,
  int *stdin_write,
  int *stdout_read
) {
  int stdin_pipe[2] = { -1, -1 };
  int stdout_pipe[2] = { -1, -1 };
  posix_spawn_file_actions_t actions;
  int actions_initialized = 0;

  if (pipe(stdin_pipe) < 0 || pipe(stdout_pipe) < 0) {
    int err = errno;
    close_if_open(&stdin_pipe[0]);
    close_if_open(&stdin_pipe[1]);
    close_if_open(&stdout_pipe[0]);
    close_if_open(&stdout_pipe[1]);
    return err;
  }

  int err = posix_spawn_file_actions_init(&actions);
  if (err != 0) {
    goto fail;
  }
  actions_initialized = 1;

  if ((err = posix_spawn_file_actions_adddup2(&actions, stdin_pipe[0], STDIN_FILENO)) != 0) {
    goto fail;
  }
  if ((err = posix_spawn_file_actions_adddup2(&actions, stdout_pipe[1], STDOUT_FILENO)) != 0) {
    goto fail;
  }
  if ((err = posix_spawn_file_actions_addclose(&actions, stdin_pipe[0])) != 0) {
    goto fail;
  }
  if ((err = posix_spawn_file_actions_addclose(&actions, stdin_pipe[1])) != 0) {
    goto fail;
  }
  if ((err = posix_spawn_file_actions_addclose(&actions, stdout_pipe[0])) != 0) {
    goto fail;
  }
  if ((err = posix_spawn_file_actions_addclose(&actions, stdout_pipe[1])) != 0) {
    goto fail;
  }

  char *argv[] = { (char *)cat_path, NULL };
  err = posix_spawn(pid, cat_path, &actions, NULL, argv, environ);
  if (err != 0) {
    goto fail;
  }

  posix_spawn_file_actions_destroy(&actions);
  close_if_open(&stdin_pipe[0]);
  close_if_open(&stdout_pipe[1]);
  *stdin_write = stdin_pipe[1];
  *stdout_read = stdout_pipe[0];
  return 0;

fail:
  if (actions_initialized) {
    posix_spawn_file_actions_destroy(&actions);
  }
  close_if_open(&stdin_pipe[0]);
  close_if_open(&stdin_pipe[1]);
  close_if_open(&stdout_pipe[0]);
  close_if_open(&stdout_pipe[1]);
  return err;
}

static int waitid_pidfd_nohang(int pidfd, siginfo_t *si) {
  memset(si, 0, sizeof(*si));
  errno = 0;
  return waitid(P_PIDFD, pidfd, si, WEXITED | WNOHANG);
}

static void print_empty_diagnostic(int iteration, pid_t pid, int pidfd, uint32_t events) {
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
    "SPURIOUS_OR_EARLY iteration=%d pid=%d pidfd=%d epoll_events=0x%x "
    "waitid(P_PID,WNOWAIT) ret=%d errno=%d si_pid=%d si_code=%d si_status=%d "
    "poll(pidfd) ret=%d errno=%d revents=0x%x kill(pid,0) ret=%d errno=%d\n",
    iteration,
    pid,
    pidfd,
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

static int reap_pidfd(int pidfd) {
  for (;;) {
    siginfo_t si;
    int ret = waitid_pidfd_nohang(pidfd, &si);
    if (ret < 0) {
      if (errno == EINTR) {
        continue;
      }
      return errno;
    }
    if (si.si_pid != 0) {
      return 0;
    }
    usleep(100);
  }
}

int main(int argc, char **argv) {
  int iterations = argc > 1 ? atoi(argv[1]) : 10000;
  const char *cat_path = argc > 2 ? argv[2] : "/bin/cat";
  int payload_len = argc > 3 ? atoi(argv[3]) : 1000;
  int max_logs = argc > 4 ? atoi(argv[4]) : 20;
  int stdout_read_len = argc > 5 ? atoi(argv[5]) : 4096;

  if (iterations <= 0 || payload_len <= 64 || stdout_read_len <= 64) {
    fprintf(
      stderr,
      "usage: %s [iterations] [cat-path] [payload-len>64] [max-logs] [stdout-read-len>64]\n",
      argv[0]
    );
    return 2;
  }
  if (stdout_read_len > 4096) {
    stdout_read_len = 4096;
  }

  char *payload = malloc((size_t)payload_len);
  if (!payload) {
    perror("malloc");
    return 2;
  }
  memset(payload, 'a', (size_t)payload_len);

  int ready_before_kill = 0;
  int empty_after_epoll = 0;
  int reaped_after_epoll = 0;
  int epoll_timeouts = 0;
  int errors = 0;

  printf(
    "pidfd SIGKILL line-limit repro: iterations=%d cat=%s payload_len=%d stdout_read_len=%d pid=%ld\n",
    iterations,
    cat_path,
    payload_len,
    stdout_read_len,
    (long)getpid()
  );

  for (int i = 0; i < iterations; i++) {
    pid_t pid = -1;
    int stdin_write = -1;
    int stdout_read = -1;
    int pidfd = -1;
    int epfd = -1;
    int child_reaped = 0;

    int err = spawn_cat(cat_path, &pid, &stdin_write, &stdout_read);
    if (err != 0) {
      errno = err;
      perror("posix_spawn cat");
      errors++;
      goto cleanup;
    }

    pidfd = xpidfd_open(pid);
    if (pidfd < 0) {
      perror("pidfd_open");
      errors++;
      goto cleanup;
    }

    int flags = fcntl(pidfd, F_GETFL);
    if (flags >= 0 && fcntl(pidfd, F_SETFL, flags | O_NONBLOCK) < 0) {
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

    struct epoll_event add_event;
    memset(&add_event, 0, sizeof(add_event));
    add_event.events = EPOLLIN;
    add_event.data.fd = pidfd;
    if (epoll_ctl(epfd, EPOLL_CTL_ADD, pidfd, &add_event) < 0) {
      perror("epoll_ctl ADD pidfd");
      errors++;
      goto cleanup;
    }

    err = write_all(stdin_write, payload, (size_t)payload_len);
    if (err != 0) {
      errno = err;
      perror("write payload");
      errors++;
      goto cleanup;
    }

    char read_buf[4096];
    ssize_t nread;
    do {
      nread = read(stdout_read, read_buf, (size_t)stdout_read_len);
    } while (nread < 0 && errno == EINTR);
    if (nread < 0) {
      perror("read stdout");
      errors++;
      goto cleanup;
    }
    if (nread <= 64) {
      fprintf(stderr, "short stdout read in iteration %d: %zd\n", i, nread);
      errors++;
      goto cleanup;
    }

    // Mimic the failing reader task unwinding after detecting the line limit.
    close_if_open(&stdout_read);
    // Mimic the stdin writer task having finished the payload and closed.
    close_if_open(&stdin_write);

    siginfo_t si;
    int ret = waitid_pidfd_nohang(pidfd, &si);
    if (ret < 0) {
      perror("initial waitid(P_PIDFD)");
      errors++;
      goto cleanup;
    }
    if (si.si_pid != 0) {
      ready_before_kill++;
      child_reaped = 1;
      goto cleanup;
    }

    if (kill(pid, SIGKILL) < 0 && errno != ESRCH) {
      perror("kill SIGKILL");
      errors++;
      goto cleanup;
    }

    struct epoll_event event;
    memset(&event, 0, sizeof(event));
    ret = epoll_wait(epfd, &event, 1, 5000);
    if (ret < 0) {
      if (errno == EINTR) {
        i--;
        goto cleanup;
      }
      perror("epoll_wait");
      errors++;
      goto cleanup;
    }
    if (ret == 0) {
      epoll_timeouts++;
      goto cleanup;
    }

    ret = waitid_pidfd_nohang(pidfd, &si);
    if (ret < 0) {
      perror("post-epoll waitid(P_PIDFD)");
      errors++;
      goto cleanup;
    }
    if (si.si_pid == 0) {
      empty_after_epoll++;
      if (empty_after_epoll <= max_logs) {
        print_empty_diagnostic(i, pid, pidfd, event.events);
      }
      err = reap_pidfd(pidfd);
      if (err != 0) {
        errno = err;
        perror("reap after empty");
        errors++;
      } else {
        child_reaped = 1;
      }
      goto cleanup;
    }

    reaped_after_epoll++;
    child_reaped = 1;

cleanup:
    close_if_open(&stdout_read);
    close_if_open(&stdin_write);
    if (pid > 0 && !child_reaped) {
      kill(pid, SIGKILL);
      waitpid(pid, NULL, 0);
    }
    close_if_open(&pidfd);
    close_if_open(&epfd);

    if ((i + 1) % 1000 == 0 || i + 1 == iterations) {
      printf(
        "progress %d/%d ready_before_kill=%d reaped_after_epoll=%d "
        "empty_after_epoll=%d epoll_timeouts=%d errors=%d\n",
        i + 1,
        iterations,
        ready_before_kill,
        reaped_after_epoll,
        empty_after_epoll,
        epoll_timeouts,
        errors
      );
    }
  }

  printf(
    "done ready_before_kill=%d reaped_after_epoll=%d empty_after_epoll=%d "
    "epoll_timeouts=%d errors=%d\n",
    ready_before_kill,
    reaped_after_epoll,
    empty_after_epoll,
    epoll_timeouts,
    errors
  );

  free(payload);
  return errors == 0 ? 0 : 1;
}
