#include <unistd.h>
#include <fcntl.h>

int moonbitlang_async_pipe(int *fds) {
  return pipe(fds);
}

int moonbitlang_async_set_nonblock(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0)
    return flags;

  if (flags & O_NONBLOCK)
    return 0;

  return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

int moonbitlang_async_set_blocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0)
    return flags;

  if (flags & O_NONBLOCK) {
    return fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);
  }

  return 0;
}

int moonbitlang_async_read(int fd, void *buf, int offset, int max_len) {
  return read(fd, buf + offset, max_len);
}

int moonbitlang_async_write(int fd, void *buf, int offset, int max_len) {
  return write(fd, buf + offset, max_len);
}
