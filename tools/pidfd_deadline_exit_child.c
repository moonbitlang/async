// Child process for pidfd deadline/signal repros.
//
// Usage:
//   pidfd_deadline_exit_child <monotonic-deadline-sec> <monotonic-deadline-nsec>

#define _GNU_SOURCE

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

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

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: %s <monotonic-deadline-sec> <monotonic-deadline-nsec>\n", argv[0]);
    return 2;
  }

  struct timespec deadline = {
    .tv_sec = (time_t)strtoll(argv[1], NULL, 10),
    .tv_nsec = strtol(argv[2], NULL, 10),
  };
  if (deadline.tv_sec < 0 || deadline.tv_nsec < 0 || deadline.tv_nsec >= 1000000000L) {
    fprintf(stderr, "invalid deadline\n");
    return 2;
  }

  if (sleep_until(deadline) < 0) {
    perror("clock_nanosleep");
    return 1;
  }

  return 0;
}
