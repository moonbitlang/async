#include <errno.h>

int moonbitlang_async_get_errno() {
  return errno;
}

int moonbitlang_async_is_nonblocking_io_error() {
  return errno == EAGAIN || errno == EINPROGRESS || errno == EWOULDBLOCK;
}
