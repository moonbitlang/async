/*
 * Copyright 2025 International Digital Economy Academy
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef _WIN32

#include <sys/wait.h>
#include <sys/types.h>
#include <string.h>
#include <signal.h>
#include <moonbit.h>

extern char **environ;

int32_t moonbitlang_async_curr_env_count() {
  int len = 0;
  for (char **cursor = environ; *cursor; ++cursor)
    ++len;
  return len;
}

int32_t moonbitlang_async_curr_env_fill_entry(
  int32_t index,
  moonbit_bytes_t out,
  int32_t out_len
) {
  int32_t len = strlen(environ[index]) + 1;
  if (len <= out_len) {
    memcpy(out, environ[index], len);
  }
  return len;
}

void moonbitlang_async_terminate_process(pid_t pid, int signal) {
  kill(pid, signal);
}

void moonbitlang_async_kill_process(pid_t pid) {
  kill(pid, SIGKILL);
}

#endif
