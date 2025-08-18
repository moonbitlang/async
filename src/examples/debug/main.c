#include <pthread.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

int channel[2];
sigset_t set;

void *worker(void *input) {
  int sig;
  int expected_sig = *(int*)input;
  for (int i = 0; ; ++i) {
    // notify the main thread that we are done
    write(channel[1], &expected_sig, sizeof(int));
    // wait for signal from the main thread
    sigwait(&set, &sig);
    if (sig != expected_sig) {
      printf("received incorrect signal at iteration %d\n", i);
      abort();
    }
  }
}

void main_prog() {
  // initialize signal set
  sigemptyset(&set);
  sigaddset(&set, SIGUSR1);
  sigaddset(&set, SIGUSR2);
  pthread_sigmask(SIG_BLOCK, &set, 0);

  // initialize the pipe
  pipe(channel);

  // create two threads
  pthread_attr_t attr;
  pthread_attr_init(&attr);

  pthread_t id1, id2;
  int thread1_expected_sig = SIGUSR1;
  int thread2_expected_sig = SIGUSR2;
  pthread_create(&id1, &attr, worker, &thread1_expected_sig);
  pthread_create(&id2, &attr, worker, &thread2_expected_sig);

  for (int i = 0; i < 10000; ++i) {
    int data[2];
    // wait for the two threads to finish processing.
    // Note that this is only for avoiding duplicated signal.
    // It does not matter if `pthread_kill` is executed before or after `sigwait`,
    // as the signal is blocked.
    read(channel[0], &data, 2 * sizeof(int));
    pthread_kill(id1, thread1_expected_sig);
    pthread_kill(id2, thread2_expected_sig);
  }

  exit(0);
}
