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

#include <moonbit.h>
#include <stdint.h>

void *moonbitlang_async_make_job(
  int32_t size,
  void (*free_job)(void *),
  int32_t (*worker)(void *, int32_t *),
  int32_t (*cancel_handler)(void *)
);

struct external_test_job {
  int32_t value;
};

static void
free_external_test_job(void *payload) {
  (void)payload;
}

static int32_t
run_external_test_job(void *payload, int32_t *error) {
  struct external_test_job *job = payload;
  *error = 0;
  return job->value;
}

MOONBIT_FFI_EXPORT
void *
moonbitlang_async_make_external_test_job(int32_t value) {
  struct external_test_job *job = moonbitlang_async_make_job(
    sizeof(struct external_test_job),
    free_external_test_job,
    run_external_test_job,
    NULL
  );
  job->value = value;
  return job;
}
