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

#include <stdlib.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <signal.h>
#include <string.h>
#include <stdio.h>
#include <moonbit.h>

extern char **environ;

char **moonbitlang_async_get_curr_env() {
  return environ;
}

int32_t moonbitlang_async_env_block_length(char **env_block) {
  for (char **cursor = env_block;; ++cursor) {
    if (*cursor == 0)
      return cursor - env_block;
  }
}

char **moonbitlang_async_allocate_env_block(int32_t size) {
  char **env_block = (char**)malloc((size + 1) * sizeof(char*));
  env_block[size] = 0;
  return env_block;
}

int32_t moonbit_utf8_len_from_utf16(
  moonbit_string_t src,
  int32_t src_offset,
  int32_t src_length
);

int32_t moonbit_utf8_encode_from_utf16(
  moonbit_string_t src,
  int32_t src_offset,
  int32_t src_length,
  moonbit_bytes_t dst, 
  int32_t dst_offset
);

int32_t moonbitlang_async_env_block_add_entry(
  char **env_block,
  int32_t index,
  moonbit_string_t key,
  int32_t key_len,
  moonbit_string_t value,
  int32_t value_len
) {
  for (int i = 0; i < key_len; ++i)
    if (key[i] == 0)
      return index;

  int key_bytes = moonbit_utf8_len_from_utf16(key, 0, key_len);
  int value_bytes = moonbit_utf8_len_from_utf16(value, 0, value_len);
  // `2`: `=` + trailing NUL
  unsigned char *entry = (unsigned char*)malloc(key_bytes + value_bytes + 2);
  moonbit_utf8_encode_from_utf16(key, 0, key_len, entry, 0);
  entry[key_bytes] = '=';
  moonbit_utf8_encode_from_utf16(value, 0, value_len, entry, key_bytes + 1);
  entry[key_bytes + value_bytes + 1] = 0;
  env_block[index] = (char*)entry; 
  return index + 1;
}

void moonbitlang_async_write_env_block(char **dst, char **env_block, int32_t base_offset) {
  for (int i = 0, offset = base_offset;; ++i) {
    char const *entry = env_block[i];
    if (entry == 0) {
      dst[offset] = 0;
      return;
    }

    int len = strlen(entry);
    char const *key_end = strchr(entry, '=');
    if (key_end) {
      for (int j = 0; j < base_offset; ++j) {
        if (strncmp(dst[j], entry, key_end + 1 - entry) == 0)
          goto skip_duplicated_entry;
      }
    } else {
      for (int j = 0; j < base_offset; ++j)
        if (strcmp(dst[j], entry) == 0)
          goto skip_duplicated_entry;
    }

    char *copied = malloc(len + 1);
    memcpy(copied, entry, len + 1);
    dst[offset++] = copied;
  skip_duplicated_entry:
    ;
  }
}


char **moonbitlang_async_make_argv_array(int32_t len) {
  char **argv = malloc((len + 1) * sizeof(char*));
  argv[len] = 0;
  return argv;
}

void moonbitlang_async_argv_array_add_encoded_entry(
  char **argv,
  int32_t offset,
  moonbit_bytes_t arg,
  int32_t arg_len
) {
  char *entry = malloc(arg_len + 1);
  memcpy(entry, arg, arg_len + 1); 
  argv[offset] = entry;
}

void moonbitlang_async_argv_array_add_entry(
  char **argv,
  int32_t offset,
  moonbit_string_t arg,
  int32_t arg_len
) {
  int len = moonbit_utf8_len_from_utf16(arg, 0, arg_len);
  char *entry = malloc(len + 1);
  moonbit_utf8_encode_from_utf16(arg, 0, arg_len, (moonbit_bytes_t)entry, 0); 
  entry[len] = 0;
  argv[offset] = entry;
}

void moonbitlang_async_terminate_process(pid_t pid, int signal) {
  kill(pid, signal);
}

void moonbitlang_async_kill_process(pid_t pid) {
  kill(pid, SIGKILL);
}

#endif
