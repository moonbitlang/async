#include <pthread.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/select.h>

int ipc[2];

void *worker1(void *input) {
  sigset_t *set = (sigset_t*)input;
  int sig;
  int data = 1;
  while (1) {
    write(ipc[1], &data, sizeof(int));
    // printf("worker 1 start waiting\n");
    sigwait(set, &sig);
    // printf("worker 1 received signal %d\n", sig);
    if (sig != SIGUSR1) {
      printf("worker 1 received incorrect signal\n");
      abort();
    }
  }
}

void *worker2(void *input) {
  sigset_t *set = (sigset_t*)input;
  int sig;
  int data = 2;
  while (1) {
    write(ipc[1], &data, sizeof(int));
    // printf("worker 2 start waiting\n");
    sigwait(set, &sig);
    // printf("worker 2 received signal %d\n", sig);
    if (sig != SIGUSR2) {
      printf("worker 2 received incorrect signal\n");
      abort();
    }
  }
}

void main_prog() {
  // initialize signal set
  sigset_t set;
  sigemptyset(&set);
  sigaddset(&set, SIGUSR1);
  sigaddset(&set, SIGUSR2);
  pthread_sigmask(SIG_BLOCK, &set, 0);

  // initialize the pipe
  pipe(ipc);
  int flags = fcntl(ipc[0], F_GETFL);
  fcntl(ipc[0], F_SETFL, flags | O_NONBLOCK);

  fd_set poll_set;
  FD_ZERO(&poll_set);
  FD_SET(ipc[0], &poll_set);

  // create two threads
  pthread_attr_t attr;
  pthread_attr_init(&attr);

  pthread_t id1, id2;
  pthread_create(&id1, &attr, worker1, &set);
  pthread_create(&id2, &attr, worker2, &set);

  for (int i = 0; i < 1000; ++i) {
    int worker1_done = 0;
    int worker2_done = 0;
    int data = 0;

    select(ipc[0] + 1, &poll_set, 0, 0, 0);
    while (read(ipc[0], &data, sizeof(int)) > 0) {
      if (data == 1)
        worker1_done = 1;
      else if (data == 2)
        worker2_done = 1;
      else {
        printf("impossible\n");
        abort();
      }
    }

    if (worker1_done) {
      // printf("sending signal %d to worker 1\n", SIGUSR1);
      pthread_kill(id1, SIGUSR1);
    }

    if (worker2_done) {
      // printf("sending signal %d to worker 2\n", SIGUSR2);
      pthread_kill(id2, SIGUSR2);
    }
  }

  exit(0);
}
