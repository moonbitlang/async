// Tiny cat-like child for pidfd/SIGKILL repros.
//
// Build with ASAN:
//   gcc -O1 -g -fno-omit-frame-pointer -fsanitize=address -Wall -Wextra tools/pidfd_repro_cat.c -o /tmp/pidfd_repro_cat_asan
//
// Optional environment:
//   PIDFD_REPRO_CAT_DELAY_US=100
//   PIDFD_REPRO_CAT_EOF_SPIN_US=100

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

static void spin_wait_us(unsigned int wait_us) {
  if (wait_us == 0) {
    return;
  }

  struct timespec start;
  clock_gettime(CLOCK_MONOTONIC, &start);
  long long target_ns = (long long)wait_us * 1000;

  for (;;) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    long long elapsed_ns =
      (long long)(now.tv_sec - start.tv_sec) * 1000000000LL +
      (long long)(now.tv_nsec - start.tv_nsec);
    if (elapsed_ns >= target_ns) {
      return;
    }
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

int main(void) {
  char *delay_env = getenv("PIDFD_REPRO_CAT_DELAY_US");
  unsigned int delay_us = delay_env ? (unsigned int)strtoul(delay_env, NULL, 10) : 0;
  char *eof_spin_env = getenv("PIDFD_REPRO_CAT_EOF_SPIN_US");
  unsigned int eof_spin_us =
    eof_spin_env ? (unsigned int)strtoul(eof_spin_env, NULL, 10) : 0;
  char buf[4096];

  for (;;) {
    ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      perror("read");
      return 1;
    }
    if (n == 0) {
      spin_wait_us(eof_spin_us);
      return 0;
    }
    int err = write_all(STDOUT_FILENO, buf, (size_t)n);
    if (err != 0) {
      errno = err;
      perror("write");
      return 1;
    }
    if (delay_us > 0) {
      usleep(delay_us);
    }
  }
}
