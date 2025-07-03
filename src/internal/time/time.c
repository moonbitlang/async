#include <stdint.h>
#include <sys/time.h>

int64_t get_ms_since_epoch() {
  struct timeval tv;
  gettimeofday(&tv, 0);
  return tv.tv_sec * 1000 + tv.tv_usec / 1000;
}
