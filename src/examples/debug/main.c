#include <pthread.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

void *worker1(void *data) {
  sigset_t *set = (sigset_t*)data;
  int sig;
  while (1) {
    printf("worker 1 start waiting\n");
    sigwait(set, &sig);
    printf("worker 1 received signal %d\n", sig);
    if (sig != SIGUSR1) abort();
  }
}

void *worker2(void *data) {
  sigset_t *set = (sigset_t*)data;
  int sig;
  while (1) {
    printf("worker 2 start waiting\n");
    sigwait(set, &sig);
    printf("worker 2 received signal %d\n", sig);
    if (sig != SIGUSR2) abort();
  }
}

void main_prog() {
  // initialize signal set
  sigset_t set;
  sigemptyset(&set);
  sigaddset(&set, SIGUSR1);
  sigaddset(&set, SIGUSR2);
  pthread_sigmask(SIG_BLOCK, &set, 0);

  // create two threads
  pthread_attr_t attr;
  pthread_attr_init(&attr);

  pthread_t id1, id2;
  pthread_create(&id1, &attr, worker1, &set);
  pthread_create(&id2, &attr, worker2, &set);

  for (int i = 0; i < 1000; ++i) {
    printf("sending signal %d to worker 1\n", SIGUSR1);
    pthread_kill(id1, SIGUSR1);

    printf("sending signal %d to worker 2\n", SIGUSR2);
    pthread_kill(id2, SIGUSR2);
  }

  exit(0);
}
