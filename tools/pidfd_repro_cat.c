// Tiny cat-like child for pidfd/SIGKILL repros.
//
// Build with ASAN:
//   gcc -O1 -g -fno-omit-frame-pointer -fsanitize=address -Wall -Wextra tools/pidfd_repro_cat.c -o /tmp/pidfd_repro_cat_asan
//
// Optional environment:
//   PIDFD_REPRO_CAT_DELAY_US=100

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

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
