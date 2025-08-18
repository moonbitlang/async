#include <pthread.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

int ipc[2];

void *worker1(void *input) {
  sigset_t *set = (sigset_t*)input;
  int sig;
  int data = 1;
  for (int i = 0; ; ++i) {
    write(ipc[1], &data, sizeof(int));
    // printf("worker 1 start waiting\n");
    sigwait(set, &sig);
    // printf("worker 1 received signal %d\n", sig);
    if (sig != SIGUSR1) {
      printf("worker 1 received incorrect signal at iteration %d\n", i);
      abort();
    }
  }
}

void *worker2(void *input) {
  sigset_t *set = (sigset_t*)input;
  int sig;
  int data = 2;
  for (int i = 0; ; ++i) {
    write(ipc[1], &data, sizeof(int));
    // printf("worker 2 start waiting\n");
    sigwait(set, &sig);
    // printf("worker 2 received signal %d\n", sig);
    if (sig != SIGUSR2) {
      printf("worker 2 received incorrect signal at iteration %d\n", i);
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

  // create two threads
  pthread_attr_t attr;
  pthread_attr_init(&attr);

  pthread_t id1, id2;
  pthread_create(&id1, &attr, worker1, &set);
  pthread_create(&id2, &attr, worker2, &set);

  for (int i = 0; i < 10000; ++i) {
    int data[2];

    read(ipc[0], &data, 2 * sizeof(int));

    // printf("sending signal %d to worker 1\n", SIGUSR1);
    pthread_kill(id1, SIGUSR1);

    // printf("sending signal %d to worker 2\n", SIGUSR2);
    pthread_kill(id2, SIGUSR2);
  }

  exit(0);
}
