#include <errno.h>

int get_errno() {
  return errno;
}

int is_nonblocking_io_error() {
  return errno == EAGAIN || errno == EINPROGRESS || errno == EWOULDBLOCK;
}
