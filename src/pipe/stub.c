#include <unistd.h>
#include <fcntl.h>

int pipe_ffi(int *fds) {
  return pipe(fds);
}

int set_nonblock(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0)
    return flags;

  if (flags & O_NONBLOCK)
    return 0;

  return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

int set_blocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0)
    return flags;

  if (flags & O_NONBLOCK) {
    return fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);
  }

  return 0;
}

int read_ffi(int fd, void *buf, int offset, int max_len) {
  return read(fd, buf + offset, max_len);
}

int write_ffi(int fd, void *buf, int offset, int max_len) {
  return write(fd, buf + offset, max_len);
}
