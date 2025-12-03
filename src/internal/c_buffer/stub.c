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

#include <string.h>
#include <stdlib.h>
#include <stdint.h>

void moonbitlang_async_blit_to_c(char *dst, char *src, int offset, int len) {
  memcpy(dst, src + offset, len);
}

void moonbitlang_async_blit_from_c(char *src, char *dst, int offset, int len) {
  memcpy(dst + offset, src, len);
}

int moonbitlang_async_c_buffer_get(uint8_t *buf, int index) {
  return buf[index];
}

int32_t moonbitlang_async_strlen(char *str) {
  return strlen(str);
}

char *moonbitlang_async_null_pointer() {
  return 0;
}

int32_t moonbitlang_async_is_null(void *ptr) {
  return ptr == 0;
}
