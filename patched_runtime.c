/*
 * Copyright 2026 International Digital Economy Academy
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

#ifdef __cplusplus
extern "C" {
#endif

#define MOONBIT_BUILD_RUNTIME
#include "moonbit.h"

#ifdef _MSC_VER
#define _Noreturn __declspec(noreturn)
#endif

#ifdef MOONBIT_NATIVE_NO_SYS_HEADER

int putchar(int c);
long write(int fd, const void *buf, size_t n);
void *malloc(size_t size);
void *realloc(void *ptr, size_t size);
void free(void *ptr);
void *memset(void *dst, int c, size_t n);
void *memcpy(void *dst, const void *src, size_t n);
void *memmove(void *dst, const void *src, size_t n);
size_t strlen(const char *s);
int strcmp(const char *s1, const char *s2);
int strncmp(const char *s1, const char *s2, size_t n);
int memcmp(const void *s1, const void *s2, size_t n);
_Noreturn void exit(int status);
_Noreturn void abort(void);

#ifndef NULL
#define NULL ((void *)0)
#endif

#else

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(MOONBIT_ALLOW_STACKTRACE) && !defined(__TINYC__)
#include <unistd.h>
#include <unwind.h>
#include "backtrace.h"

#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif // #if defined(__APPLE__)

// Set maximum number of backtrace frames to print.
#define BACKTRACE_LIMIT 15

#endif // #if defined(MOONBIT_ALLOW_STACKTRACE) && !defined(__TINYC__)

#endif

// header manipulation macros
#define Moonbit_header_ptr_field_offset(header)                                \
  ((header >> 19) & (((uint32_t)1 << 11) - 1))

#define Moonbit_header_ptr_field_count(header)                                 \
  ((header >> 8) & (((uint32_t)1 << 11) - 1))

#define Moonbit_object_ptr_field_offset(obj)                                   \
  (Moonbit_header_ptr_field_offset(Moonbit_object_header(obj)->meta))

#define Moonbit_object_ptr_field_count(obj)                                    \
  (Moonbit_header_ptr_field_count(Moonbit_object_header(obj)->meta))

MOONBIT_EXPORT void *libc_malloc(size_t size) { return malloc(size); }
MOONBIT_EXPORT void libc_free(void *ptr) { free(ptr); }

MOONBIT_EXPORT void *moonbit_malloc(size_t size) {
  struct moonbit_object *ptr =
      (struct moonbit_object *)malloc(sizeof(struct moonbit_object) + size);
  ptr->rc = 1;
  return ptr + 1;
}

#define moonbit_free(obj) free(Moonbit_object_header(obj))

MOONBIT_EXPORT void moonbit_drop_object(void *obj) {
  /* `moonbit_drop_object`:

     - perform `decref` on all children of `obj`
       - recursively drop children whose count dropped to zero
     - free the memory occupied by `obj`

     We want to avoid stackoverflow when dropping a deep object.
     Here's an algorithm with O(1) stack requirement and zero heap allocation.
     Traversing the object graph itself requires `O(d)` space (depth of object),
     but since we are dropping objects,
     we can *reuse the memory of to-be-dropped objects* to store traversal
     state.

     Everytime we dive down into a child, we need to remember the following
     states:

     - our position in the middle of current object (`int32_t`)
     - how many objects remaining in current object (`int32_t`)
     - the parent of current object (`void*`)

     Fortunately, we have exactly the space required in to-be-dropped current
     object:

     - current position is stored in the `(struct moonbit_object).rc` field
     - remaining children count is stored in the `(struct moonbit_object).meta`
     field
     - parent is stored in the place where current visited object was previously
     stored

     The control flow of the algorithm is quite complex,
     here it is represented as three big goto-blocks:

     - `handle_new_object`: drop a new object not visited previously

     - `back_to_parent`: we have finished processing current object,
       move back to its parent and process remaining children of its parent

     - `process_children`: perform `decref` on the children of current object,
       resuming from a position in the middle
  */

  /* States maintained in the algorithm:

     - `obj`: the object currently being processed
     - `parent`: the parent of `obj`, `0` if `obj` is the root
     - `curr_child_offset`: the offset of the first unprocessed child in `obj`,
       counted in `uint32_t`, starting from `obj`
     - `remaining_children_count`: the number of unprocessed child in `obj`

     `curr_child_offset` and `remaining_children_count`, are used by
     `process_children`. So they must be valid before entering
     `process_children`
  */
  void *parent = 0;
  int32_t curr_child_offset, remaining_children_count;
handle_new_object:
  /* If current object has any children, jump to `process_children`,
     otherwise, we have finished processing current object, fallthrough to
     `back_to_parent`.
  */
  switch (Moonbit_object_kind(obj)) {
  case moonbit_BLOCK_KIND_REGULAR: {
    const int32_t ptr_field_offset = Moonbit_object_ptr_field_offset(obj);
    const int32_t n_ptr_fields = Moonbit_object_ptr_field_count(obj);
    if (n_ptr_fields > 0) {
      curr_child_offset = ptr_field_offset;
      remaining_children_count = n_ptr_fields;
      goto process_children;
    }
    break;
  }
  case moonbit_BLOCK_KIND_REF_ARRAY: {
    int32_t len = Moonbit_array_length(obj);
    const int32_t elem_size = Moonbit_array_elem_size_shift(obj);
    if (len > 0) {
      if (elem_size == moonbit_REF_ARRAY_REF_VALTYPE) {
        // mixed value type array
        uint32_t valtype_header = Moonbit_valtype_header(obj)->elem_header;
        const int32_t ptr_field_offset =
            Moonbit_header_ptr_field_offset(valtype_header);
        const int32_t n_ptr_fields =
            Moonbit_header_ptr_field_count(valtype_header);
        void *cur_elem = obj;
        void **ptrs;
        for (int32_t i = 0; i < len; ++i) {
          ptrs = (void **)((uint32_t *)cur_elem + ptr_field_offset);
          for (int32_t j = 0; j < n_ptr_fields; ++j) {
            if (ptrs[j])
              moonbit_decref(ptrs[j]);
          }
          cur_elem = &ptrs[n_ptr_fields];
        }
        // The array of ref value type will be freed.
        // We move the pointer backward for the size of the value type header.
        // So that the regular free logic can be used.
        obj = (uint64_t *)obj - 1;
      } else {
        // regular array
        curr_child_offset = 0;
        remaining_children_count = len;
        goto process_children;
      }
    }
    break;
  }
  case moonbit_BLOCK_KIND_VAL_ARRAY:
    break;
  case moonbit_BLOCK_KIND_EXTERNAL: {
    int32_t payload_size = Moonbit_object_header(obj)->meta & ((1 << 30) - 1);
    void (**addr_of_finalize)(void *) =
        (void (**)(void *))((uint8_t *)obj + payload_size);
    (**addr_of_finalize)(obj);
    break;
  }
  }

back_to_parent:
  moonbit_free(obj);
  if (!parent)
    return;

  // Recover stored traversal state from the memory of parent
  curr_child_offset = Moonbit_object_header(parent)->rc;
  remaining_children_count = Moonbit_object_header(parent)->meta;
  obj = parent;
  parent = *(void **)((uint32_t *)parent + curr_child_offset);
  // We have finished processing one object, so move forward by one slot
  curr_child_offset += sizeof(void *) >> 2;
  // Fallthrough to `process_children`, resuming handling of parent

process_children:
  // `curr_child_offset` and `remaining_children_count` must be properly set
  // here.
  while (remaining_children_count > 0) {
    void *next = *(void **)((uint32_t *)obj + curr_child_offset);
    remaining_children_count -= 1;
    if (next) {
      struct moonbit_object *header = Moonbit_object_header(next);
      int32_t const count = header->rc;
      if (count > 1) {
        // This child is still alive, continue with remaining children
        header->rc = count - 1;
      } else if (count == 1) {
        /* This child should be recursively dropped.
           Before diving into the child, store current traveral state in `obj`
        */
        if (remaining_children_count == 0) {
          /* "tail call" optimization: if we are diving into the last child,
             there is no need to process current object when we go back,
             because we know current object has no more children.
             So we can:

             - free current object immediately
             - don't touch `parent`, so it is still parent of `obj`.
               This way, when we go back from `next`,
               we would jump to `parent` directly, skipping `obj`

             This optimization can save a complete iteration of the object graph
             when dropping structures like linked list.
          */
          moonbit_free(obj);
        } else {
          Moonbit_object_header(obj)->rc = curr_child_offset;
          Moonbit_object_header(obj)->meta = remaining_children_count;
          *(void **)((uint32_t *)obj + curr_child_offset) = parent;
          parent = obj;
        }
        obj = next;
        goto handle_new_object;
      }
    }
    curr_child_offset += sizeof(void *) >> 2;
  }
  // `remaining_children_count = 0`, all children processed
  goto back_to_parent;
}

MOONBIT_EXPORT void moonbit_incref(void *ptr) {
  struct moonbit_object *header = Moonbit_object_header(ptr);
  int32_t const count = header->rc;
  if (count > 0) {
    header->rc = count + 1;
  }
}

MOONBIT_EXPORT void moonbit_decref(void *ptr) {
  struct moonbit_object *header = Moonbit_object_header(ptr);
  int32_t const count = header->rc;
  if (count > 1) {
    header->rc = count - 1;
  } else if (count == 1) {
    moonbit_drop_object(ptr);
  }
}

#if defined(MOONBIT_ALLOW_STACKTRACE) && !defined(__TINYC__)

// Forward declaration
static const char *demangle(const char *func_name, char **owned_out);
static void error_callback(void *data, const char *msg, int errnum);

typedef struct {
  struct backtrace_state *state;
  int count;
  int limit_reached;
  int has_meaningful_frame;
  int consecutive_unknown;
  int stop_unwinding;
} mbt_backtrace_data;

static int symbolize_callback(void *data, uintptr_t pc, const char *filename, int lineno, const char *function) {
  mbt_backtrace_data *bt_data = (mbt_backtrace_data *)data;
  
  if (bt_data->limit_reached) return 0;

  if (function && (strstr(function, "moonbit_panic") || strstr(function, "unwind_callback"))) {
    return 0;
  }

  int is_meaningful = (filename != NULL) || (function != NULL);
  
  if (bt_data->has_meaningful_frame && !is_meaningful && lineno == 0) {
    bt_data->consecutive_unknown++;
    if (bt_data->consecutive_unknown > 1) {
      bt_data->stop_unwinding = 1;
      return 0;
    }
  } else {
    bt_data->consecutive_unknown = 0;
    if (is_meaningful) {
      bt_data->has_meaningful_frame = 1;
    }
  }

  if (bt_data->count >= BACKTRACE_LIMIT) {
    fprintf(stderr, "    ...\n");
    
    bt_data->limit_reached = 1;
    return 0;
  }

  char *owned_name = NULL;
  const char *func_name = function ? demangle(function, &owned_name) : "???";
  const char *file_name = filename ? filename : "???";

  fprintf(stderr, "    at %s (%s:%d)\n", func_name, file_name, lineno);

  bt_data->count++;
  free(owned_name);
  return 0;
}

static _Unwind_Reason_Code unwind_callback(struct _Unwind_Context *ctx, void *arg) {
  mbt_backtrace_data *bt_data = (mbt_backtrace_data *)arg;
  
  if (bt_data->limit_reached || bt_data->stop_unwinding) {
    return _URC_END_OF_STACK;
  }
  
  uintptr_t pc = _Unwind_GetIP(ctx);
  if (pc == 0) return _URC_END_OF_STACK;

  backtrace_pcinfo(bt_data->state, pc - 1, symbolize_callback, error_callback, bt_data);

  if (bt_data->stop_unwinding) {
    return _URC_END_OF_STACK;
  }

  return _URC_NO_REASON;
}

static void error_callback(void *data, const char *msg, int errnum) {
  fprintf(stderr, "libbacktrace error: %s (%d)\n", msg, errnum);
}

#endif // #if defined(MOONBIT_ALLOW_STACKTRACE) && !defined(__TINYC__)

#ifdef _WIN32
#include <windows.h>
#include <dbghelp.h>
#pragma comment(lib, "Kernel32.lib")
#pragma comment(lib, "DbgHelp.lib")
#endif

MOONBIT_EXPORT _Noreturn void moonbit_panic(void) {
#if defined(MOONBIT_ALLOW_STACKTRACE) && !defined(__TINYC__)
  fflush(stdout);
  fprintf(stderr, "PanicError\n");

  static struct backtrace_state *state = NULL;
  if (!state) {
    static char exec_path[1024];
    uint32_t size = sizeof(exec_path);
    const char* path_ptr = NULL;

#if defined(__APPLE__)
    if (_NSGetExecutablePath(exec_path, &size) == 0) {
      path_ptr = exec_path;
    }
#elif defined(__linux__)
    ssize_t len = readlink("/proc/self/exe", exec_path, sizeof(exec_path)-1);
    if (len != -1) {
      exec_path[len] = '\0';
      path_ptr = exec_path;
    }
#endif // #if defined(__APPLE__)
    state = backtrace_create_state(path_ptr, 1, error_callback, NULL);
  }

  if (state) {
    mbt_backtrace_data bt_data = {state, 0, 0, 0, 0, 0};
    _Unwind_Backtrace(unwind_callback, &bt_data);
  }
#elif defined(_MSC_VER) // #if defined(MOONBIT_ALLOW_STACKTRACE) && !defined(__TINYC__)
  void *frames[100];
  int n = CaptureStackBackTrace(0, 100, frames, NULL);
  HANDLE self = GetCurrentProcess();
  if (!SymInitialize(self, NULL, TRUE))
    fprintf(stderr, "`SymInitialize` failed with %d\n", GetLastError());
  fprintf(stderr, "panic!\nstacktrace:\n");
  for (int i = 0; i < n; ++i) {
    void *frame = frames[i];
    SYMBOL_INFO *symbol = malloc(sizeof(SYMBOL_INFO) + 256);
    symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
    symbol->MaxNameLen = 255;
    if (!SymFromAddr(self, frame, NULL, symbol)) {
      fprintf(stderr, "  unknown function at %lld | `SymFromAddr` failed with %d\n", (uint64_t)frame, GetLastError());
    } else {
      fprintf(stderr, "  %s\n", symbol->Name);
    }
  }
#endif

#ifdef MOONBIT_NATIVE_EXIT_ON_PANIC
  exit(1);
#else
  abort();
#endif
}

/* ------------------------------------------------------------- */
/* Optional: integrate with TinyCC (-run) backtrace facility.
   TinyCC's tccrun.c supports a per-frame callback (TCCBtFunc) when a runtime
   exception / SIGABRT happens. We expose a callback symbol that can be
   discovered by the host (tcc -run) and used to build a backtrace string and
   print it.

   Notes:
   - Keep this code independent from libc headers: it must compile with
     MOONBIT_NATIVE_NO_SYS_HEADER.
   - The host (TinyCC) decides whether to call this function.
*/

static void moonbit__eprint_n(const char *s, size_t n) {
  if (!s || n == 0)
    return;
#ifdef MOONBIT_NATIVE_NO_SYS_HEADER
  while (n) {
    /* Best-effort write to stderr; retry a few times to handle EINTR-like
       transient failures without needing errno. Retries are bounded. */
    int tries = 0;
    long r = write(2, s, n);
    while (r < 0 && tries < 3) {
      tries++;
      r = write(2, s, n);
    }
    if (r <= 0)
      break;
    s += (size_t)r;
    n -= (size_t)r;
  }
#else
  (void)fwrite(s, 1, n, stderr);
  (void)fflush(stderr);
#endif
}

static void moonbit__eprint(const char *s) {
  if (!s)
    return;
  moonbit__eprint_n(s, strlen(s));
}

static void moonbit__bt_buf_append_char(char *buf, size_t cap, size_t *len,
                                        char c) {
  /* Need space for the char and a trailing '\0'. Use subtraction to avoid
     potential overflow in *len + 2. */
  if (cap == 0 || *len >= cap || (cap - *len) < 2)
    return;
  buf[*len] = c;
  *len += 1;
  buf[*len] = 0;
}

static void moonbit__bt_buf_append_cstr(char *buf, size_t cap, size_t *len,
                                        const char *s) {
  if (!s)
    return;
  for (size_t i = 0; s[i]; i++)
    moonbit__bt_buf_append_char(buf, cap, len, s[i]);
}

static void moonbit__bt_buf_append_u32_dec(char *buf, size_t cap, size_t *len,
                                           uint32_t x) {
  char tmp[16];
  int n = 0;
  if (x == 0) {
    moonbit__bt_buf_append_char(buf, cap, len, '0');
    return;
  }
  while (x && n < (int)sizeof(tmp)) {
    tmp[n++] = (char)('0' + (x % 10));
    x /= 10;
  }
  while (n-- > 0)
    moonbit__bt_buf_append_char(buf, cap, len, tmp[n]);
}

static void moonbit__bt_buf_append_ptr_hex(char *buf, size_t cap, size_t *len,
                                           uintptr_t p) {
  static const char hexdig[] = "0123456789abcdef";
  /* Need "0x" + 2*bytes characters, plus trailing '\0'. */
  const size_t need_chars = 2 + (sizeof(uintptr_t) * 2);
  if (cap == 0 || *len >= cap)
    return;
  if ((cap - *len) < (need_chars + 1)) {
    moonbit__bt_buf_append_cstr(buf, cap, len, "0x?");
    return;
  }
  moonbit__bt_buf_append_cstr(buf, cap, len, "0x");
  for (int i = (int)(sizeof(uintptr_t) * 2) - 1; i >= 0; i--) {
    unsigned shift = (unsigned)i * 4;
    moonbit__bt_buf_append_char(buf, cap, len,
                                hexdig[(p >> shift) & 0xF]);
  }
}

static uint32_t moonbit__bt_level = 0;

#ifndef MOONBIT_NATIVE_BT_MAX_FRAMES
#define MOONBIT_NATIVE_BT_MAX_FRAMES 64
#endif

typedef struct {
  char *buf;
  size_t len;
  size_t cap;
} mbt_str;

static int mbt_str_reserve(mbt_str *s, size_t extra) {
  if (s->len + extra + 1 <= s->cap)
    return 1;
  size_t next_cap = s->cap ? s->cap : 64;
  while (next_cap < s->len + extra + 1)
    next_cap *= 2;
  char *next = (char *)realloc(s->buf, next_cap);
  if (!next)
    return 0;
  s->buf = next;
  s->cap = next_cap;
  return 1;
}

static int mbt_str_init(mbt_str *s) {
  s->buf = NULL;
  s->len = 0;
  s->cap = 0;
  return mbt_str_reserve(s, 0);
}

static int mbt_str_append_char(mbt_str *s, char c) {
  if (!mbt_str_reserve(s, 1))
    return 0;
  s->buf[s->len++] = c;
  s->buf[s->len] = 0;
  return 1;
}

static int mbt_str_append_cstr(mbt_str *s, const char *cstr) {
  if (!cstr)
    return 1;
  for (size_t i = 0; cstr[i]; i++) {
    if (!mbt_str_append_char(s, cstr[i]))
      return 0;
  }
  return 1;
}

static int mbt_str_append_n(mbt_str *s, const char *cstr, size_t n) {
  if (!cstr || n == 0)
    return 1;
  if (!mbt_str_reserve(s, n))
    return 0;
  memcpy(s->buf + s->len, cstr, n);
  s->len += n;
  s->buf[s->len] = 0;
  return 1;
}

static char *mbt_str_release(mbt_str *s) {
  char *out = s->buf;
  s->buf = NULL;
  s->len = 0;
  s->cap = 0;
  return out;
}

static int mbt_dup_cstr(const char *src, char **out) {
  size_t n = strlen(src);
  char *dst = (char *)malloc(n + 1);
  if (!dst)
    return 0;
  memcpy(dst, src, n + 1);
  *out = dst;
  return 1;
}

static int mbt_parse_u32(const char **p, uint32_t *out) {
  const char *cur = *p;
  if (*cur < '0' || *cur > '9')
    return 0;
  uint32_t v = 0;
  while (*cur >= '0' && *cur <= '9') {
    uint32_t d = (uint32_t)(*cur - '0');
    v = v * 10 + d;
    cur++;
  }
  *p = cur;
  *out = v;
  return 1;
}

static int mbt_hex_value(char c) {
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return 10 + (c - 'a');
  if (c >= 'A' && c <= 'F')
    return 10 + (c - 'A');
  return -1;
}

static int mbt_parse_identifier(const char **p, char **out) {
  uint32_t n = 0;
  if (!mbt_parse_u32(p, &n))
    return 0;
  const char *start = *p;
  size_t remaining = strlen(start);
  if (remaining < (size_t)n)
    return 0;
  *p = start + n;

  mbt_str decoded;
  if (!mbt_str_init(&decoded))
    return 0;
  for (uint32_t i = 0; i < n; i++) {
    char c = start[i];
    if (c != '_') {
      if (!mbt_str_append_char(&decoded, c)) {
        free(decoded.buf);
        return 0;
      }
      continue;
    }
    if (i + 1 >= n) {
      free(decoded.buf);
      return 0;
    }
    char next = start[i + 1];
    if (next == '_') {
      if (!mbt_str_append_char(&decoded, '_')) {
        free(decoded.buf);
        return 0;
      }
      i += 1;
      continue;
    }
    if (i + 2 >= n) {
      free(decoded.buf);
      return 0;
    }
    int hi = mbt_hex_value(start[i + 1]);
    int lo = mbt_hex_value(start[i + 2]);
    if (hi < 0 || lo < 0) {
      free(decoded.buf);
      return 0;
    }
    char v = (char)((hi << 4) | lo);
    if (!mbt_str_append_char(&decoded, v)) {
      free(decoded.buf);
      return 0;
    }
    i += 2;
  }
  *out = mbt_str_release(&decoded);
  return 1;
}

static int mbt_parse_package_segments(const char **p, uint32_t count,
                                      char **out_pkg) {
  mbt_str pkg;
  if (!mbt_str_init(&pkg))
    return 0;
  for (uint32_t i = 0; i < count; i++) {
    char *seg = NULL;
    if (!mbt_parse_identifier(p, &seg)) {
      free(pkg.buf);
      return 0;
    }
    if (i > 0 && !mbt_str_append_char(&pkg, '/')) {
      free(seg);
      free(pkg.buf);
      return 0;
    }
    if (!mbt_str_append_cstr(&pkg, seg)) {
      free(seg);
      free(pkg.buf);
      return 0;
    }
    free(seg);
  }
  *out_pkg = mbt_str_release(&pkg);
  return 1;
}

static int mbt_parse_package(const char **p, char **out_pkg) {
  if (**p != 'P')
    return 0;
  (*p)++;

  if (**p == 'B') {
    (*p)++;
    return mbt_dup_cstr("moonbitlang/core/builtin", out_pkg);
  }

  if (**p == 'C') {
    (*p)++;
    const char *count_start = *p;
    uint32_t count = 0;
    if (!mbt_parse_u32(p, &count))
      return 0;

    char *suffix = NULL;
    if (!mbt_parse_package_segments(p, count, &suffix)) {
      *p = count_start;
      if (**p < '0' || **p > '9')
        return 0;
      count = (uint32_t)(**p - '0');
      (*p)++;
      if (!mbt_parse_package_segments(p, count, &suffix))
        return 0;
    }

    mbt_str full;
    if (!mbt_str_init(&full)) {
      free(suffix);
      return 0;
    }
    if (!mbt_str_append_cstr(&full, "moonbitlang/core") ||
        (suffix[0] && (!mbt_str_append_char(&full, '/') ||
                       !mbt_str_append_cstr(&full, suffix)))) {
      free(suffix);
      free(full.buf);
      return 0;
    }
    free(suffix);
    *out_pkg = mbt_str_release(&full);
    return 1;
  }

  const char *count_start = *p;
  uint32_t count = 0;
  if (!mbt_parse_u32(p, &count))
    return 0;
  if (mbt_parse_package_segments(p, count, out_pkg))
    return 1;

  *p = count_start;
  if (**p < '0' || **p > '9')
    return 0;
  count = (uint32_t)(**p - '0');
  (*p)++;
  return mbt_parse_package_segments(p, count, out_pkg);
}

static int mbt_pkg_is_core(const char *pkg) {
  if (!pkg || !pkg[0])
    return 0;
  const char *prefix = "moonbitlang/core";
  size_t n = strlen(prefix);
  if (strncmp(pkg, prefix, n) != 0)
    return 0;
  return pkg[n] == 0 || pkg[n] == '/';
}

static int mbt_append_type_path(const char **p, mbt_str *out,
                                int omit_core_prefix) {
  char *pkg = NULL;
  char *type = NULL;
  if (!mbt_parse_package(p, &pkg))
    return 0;
  if (!mbt_parse_identifier(p, &type)) {
    free(pkg);
    return 0;
  }
  if (**p == 'L') {
    (*p)++;
    char *local = NULL;
    if (!mbt_parse_identifier(p, &local)) {
      free(pkg);
      free(type);
      return 0;
    }
    mbt_str combined;
    if (!mbt_str_init(&combined)) {
      free(pkg);
      free(type);
      free(local);
      return 0;
    }
    if (!mbt_str_append_cstr(&combined, type) ||
        !mbt_str_append_char(&combined, '.') ||
        !mbt_str_append_cstr(&combined, local)) {
      free(pkg);
      free(type);
      free(local);
      free(combined.buf);
      return 0;
    }
    free(type);
    free(local);
    type = mbt_str_release(&combined);
  }

  const char *pkg_use = pkg;
  if (omit_core_prefix && mbt_pkg_is_core(pkg))
    pkg_use = "";

  if (!mbt_str_append_char(out, '@')) {
    free(pkg);
    free(type);
    return 0;
  }
  if (pkg_use && pkg_use[0]) {
    if (!mbt_str_append_cstr(out, pkg_use) ||
        !mbt_str_append_char(out, '.')) {
      free(pkg);
      free(type);
      return 0;
    }
  }
  if (!mbt_str_append_cstr(out, type)) {
    free(pkg);
    free(type);
    return 0;
  }
  free(pkg);
  free(type);
  return 1;
}

static int mbt_parse_type_arg(const char **p, mbt_str *out);

static int mbt_parse_type_args(const char **p, mbt_str *out) {
  if (**p == 'H') {
    (*p)++;
    if (!mbt_str_append_cstr(out, " raise "))
      return 0;
    return mbt_parse_type_arg(p, out);
  }
  if (**p != 'G')
    return 1;
  (*p)++;
  if (!mbt_str_append_char(out, '['))
    return 0;
  int first = 1;
  while (**p && **p != 'E') {
    if (!first) {
      if (!mbt_str_append_cstr(out, ", "))
        return 0;
    }
    if (!mbt_parse_type_arg(p, out))
      return 0;
    first = 0;
  }
  if (**p != 'E')
    return 0;
  (*p)++;
  if (!mbt_str_append_char(out, ']'))
    return 0;
  if (**p == 'H') {
    (*p)++;
    if (!mbt_str_append_cstr(out, " raise "))
      return 0;
    if (!mbt_parse_type_arg(p, out))
      return 0;
  }
  return 1;
}

static int mbt_parse_fn_type(const char **p, mbt_str *out, int async_mark) {
  if (**p != 'W')
    return 0;
  (*p)++;
  if (async_mark && !mbt_str_append_cstr(out, "async "))
    return 0;
  if (!mbt_str_append_char(out, '('))
    return 0;
  int first = 1;
  while (**p && **p != 'E') {
    if (!first) {
      if (!mbt_str_append_cstr(out, ", "))
        return 0;
    }
    if (!mbt_parse_type_arg(p, out))
      return 0;
    first = 0;
  }
  if (**p != 'E')
    return 0;
  (*p)++;
  if (!mbt_str_append_cstr(out, ") -> "))
    return 0;
  if (!mbt_parse_type_arg(p, out))
    return 0;
  if (**p == 'Q') {
    (*p)++;
    if (!mbt_str_append_cstr(out, " raise "))
      return 0;
    if (!mbt_parse_type_arg(p, out))
      return 0;
  }
  return 1;
}

static int mbt_parse_type_ref(const char **p, mbt_str *out) {
  if (**p != 'R')
    return 0;
  (*p)++;
  if (!mbt_append_type_path(p, out, 0))
    return 0;
  if (**p == 'G') {
    if (!mbt_parse_type_args(p, out))
      return 0;
  }
  return 1;
}

static int mbt_parse_type_arg(const char **p, mbt_str *out) {
  char c = **p;
  if (!c)
    return 0;
  switch (c) {
    case 'i': (*p)++; return mbt_str_append_cstr(out, "Int");
    case 'l': (*p)++; return mbt_str_append_cstr(out, "Int64");
    case 'h': (*p)++; return mbt_str_append_cstr(out, "Int16");
    case 'j': (*p)++; return mbt_str_append_cstr(out, "UInt");
    case 'k': (*p)++; return mbt_str_append_cstr(out, "UInt16");
    case 'm': (*p)++; return mbt_str_append_cstr(out, "UInt64");
    case 'd': (*p)++; return mbt_str_append_cstr(out, "Double");
    case 'f': (*p)++; return mbt_str_append_cstr(out, "Float");
    case 'b': (*p)++; return mbt_str_append_cstr(out, "Bool");
    case 'c': (*p)++; return mbt_str_append_cstr(out, "Char");
    case 's': (*p)++; return mbt_str_append_cstr(out, "String");
    case 'u': (*p)++; return mbt_str_append_cstr(out, "Unit");
    case 'y': (*p)++; return mbt_str_append_cstr(out, "Byte");
    case 'z': (*p)++; return mbt_str_append_cstr(out, "Bytes");
    case 'A': {
      (*p)++;
      if (!mbt_str_append_cstr(out, "FixedArray["))
        return 0;
      if (!mbt_parse_type_arg(p, out))
        return 0;
      return mbt_str_append_char(out, ']');
    }
    case 'O': {
      (*p)++;
      if (!mbt_str_append_cstr(out, "Option["))
        return 0;
      if (!mbt_parse_type_arg(p, out))
        return 0;
      return mbt_str_append_char(out, ']');
    }
    case 'U': {
      (*p)++;
      if (!mbt_str_append_char(out, '('))
        return 0;
      int first = 1;
      while (**p && **p != 'E') {
        if (!first) {
          if (!mbt_str_append_cstr(out, ", "))
            return 0;
        }
        if (!mbt_parse_type_arg(p, out))
          return 0;
        first = 0;
      }
      if (**p != 'E')
        return 0;
      (*p)++;
      return mbt_str_append_char(out, ')');
    }
    case 'V':
      (*p)++;
      return mbt_parse_fn_type(p, out, 1);
    case 'W':
      return mbt_parse_fn_type(p, out, 0);
    case 'R':
      return mbt_parse_type_ref(p, out);
    default:
      return 0;
  }
}

static int mbt_skip_decimal(const char **p) {
  if (**p < '0' || **p > '9')
    return 0;
  while (**p >= '0' && **p <= '9')
    (*p)++;
  return 1;
}

static int mbt_parse_decimal_span(const char **p, const char **start, size_t *len) {
  const char *s = *p;
  if (*s < '0' || *s > '9')
    return 0;
  while (**p >= '0' && **p <= '9')
    (*p)++;
  *start = s;
  *len = (size_t)(*p - s);
  return 1;
}

static int mbt_parse_lifted_suffixes(const char **p, mbt_str *out) {
  while (**p == 'N') {
    (*p)++;
    char *nested = NULL;
    if (!mbt_parse_identifier(p, &nested))
      return 0;
    if (**p != 'S') {
      free(nested);
      return 0;
    }
    (*p)++;
    if (!mbt_skip_decimal(p)) {
      free(nested);
      return 0;
    }
    if (!mbt_str_append_char(out, '.') || !mbt_str_append_cstr(out, nested)) {
      free(nested);
      return 0;
    }
    free(nested);
  }
  return 1;
}

static int mbt_parse_closure_suffix(const char **p, mbt_str *out) {
  if (**p != 'C')
    return 1;
  (*p)++;
  if (**p < '0' || **p > '9')
    return 0;

  const char *uuid = NULL;
  size_t uuid_len = 0;
  if (!mbt_parse_decimal_span(p, &uuid, &uuid_len))
    return 0;

  if (**p == 'l') {
    const char *line = NULL;
    size_t line_len = 0;
    (*p)++;
    if (!mbt_parse_decimal_span(p, &line, &line_len))
      return 0;
    return mbt_str_append_cstr(out, ".anon(l") &&
           mbt_str_append_n(out, line, line_len) &&
           mbt_str_append_char(out, ')');
  }

  (void)uuid;
  (void)uuid_len;
  return mbt_str_append_cstr(out, ".anon");
}

static int mbt_parse_fn_suffixes(const char **p, mbt_str *out) {
  if (!mbt_parse_lifted_suffixes(p, out))
    return 0;
  if (!mbt_parse_closure_suffix(p, out))
    return 0;
  return 1;
}

static int demangle_tag_F(const char **p, mbt_str *out) {
  int ok = 1;
  char *pkg = NULL;
  char *name = NULL;
  if (!mbt_parse_package(p, &pkg) || !mbt_parse_identifier(p, &name)) {
    ok = 0;
  } else if (!mbt_str_append_char(out, '@') ||
             (pkg && pkg[0] && (!mbt_str_append_cstr(out, pkg) ||
                                !mbt_str_append_char(out, '.'))) ||
             !mbt_str_append_cstr(out, name)) {
    ok = 0;
  }
  free(pkg);
  free(name);
  if (ok && !mbt_parse_fn_suffixes(p, out))
    ok = 0;
  if (ok && (**p == 'G' || **p == 'H')) {
    if (!mbt_parse_type_args(p, out))
      ok = 0;
  }
  if (ok && !mbt_parse_fn_suffixes(p, out))
    ok = 0;
  return ok;
}

static int demangle_tag_M(const char **p, mbt_str *out) {
  int ok = 1;
  char *pkg = NULL;
  char *type = NULL;
  char *name = NULL;
  if (!mbt_parse_package(p, &pkg) || !mbt_parse_identifier(p, &type) ||
      !mbt_parse_identifier(p, &name)) {
    ok = 0;
  } else if (!mbt_str_append_char(out, '@') ||
             (pkg && pkg[0] && (!mbt_str_append_cstr(out, pkg) ||
                                !mbt_str_append_char(out, '.'))) ||
             !mbt_str_append_cstr(out, type) ||
             !mbt_str_append_cstr(out, "::") ||
             !mbt_str_append_cstr(out, name)) {
    ok = 0;
  }
  free(pkg);
  free(type);
  free(name);
  if (ok && !mbt_parse_fn_suffixes(p, out))
    ok = 0;
  if (ok && (**p == 'G' || **p == 'H')) {
    if (!mbt_parse_type_args(p, out))
      ok = 0;
  }
  if (ok && !mbt_parse_fn_suffixes(p, out))
    ok = 0;
  return ok;
}

static int demangle_tag_I(const char **p, mbt_str *out) {
  int ok = 1;
  mbt_str impl_type;
  mbt_str trait_type;
  mbt_str type_args;
  mbt_str fn_suffix;
  int impl_inited = 0;
  int trait_inited = 0;
  int args_inited = 0;
  int suffix_inited = 0;

  if (mbt_str_init(&impl_type))
    impl_inited = 1;
  if (mbt_str_init(&trait_type))
    trait_inited = 1;
  if (mbt_str_init(&type_args))
    args_inited = 1;
  if (mbt_str_init(&fn_suffix))
    suffix_inited = 1;
  if (!impl_inited || !trait_inited || !args_inited || !suffix_inited)
    ok = 0;

  if (ok && (!mbt_append_type_path(p, &impl_type, 0) ||
             !mbt_append_type_path(p, &trait_type, 0)))
    ok = 0;

  char *name = NULL;
  if (ok && !mbt_parse_identifier(p, &name))
    ok = 0;
  if (ok && !mbt_parse_fn_suffixes(p, &fn_suffix))
    ok = 0;
  if (ok && (**p == 'G' || **p == 'H')) {
    if (!mbt_parse_type_args(p, &type_args))
      ok = 0;
  }
  if (ok && !mbt_parse_fn_suffixes(p, &fn_suffix))
    ok = 0;

  if (ok && (!mbt_str_append_cstr(out, "impl ") ||
             !mbt_str_append_cstr(out, trait_type.buf) ||
             !mbt_str_append_cstr(out, " for ") ||
             !mbt_str_append_cstr(out, impl_type.buf) ||
             (type_args.len && !mbt_str_append_cstr(out, type_args.buf)) ||
             !mbt_str_append_cstr(out, " with ") ||
             !mbt_str_append_cstr(out, name) ||
             (fn_suffix.len && !mbt_str_append_cstr(out, fn_suffix.buf))))
    ok = 0;

  if (impl_inited)
    free(impl_type.buf);
  if (trait_inited)
    free(trait_type.buf);
  if (args_inited)
    free(type_args.buf);
  if (suffix_inited)
    free(fn_suffix.buf);
  free(name);
  return ok;
}

static int demangle_tag_E(const char **p, mbt_str *out) {
  int ok = 1;
  char *type_pkg = NULL;
  char *type_name = NULL;
  char *method_pkg = NULL;
  char *method_name = NULL;
  if (!mbt_parse_package(p, &type_pkg) ||
      !mbt_parse_identifier(p, &type_name) ||
      !mbt_parse_package(p, &method_pkg) ||
      !mbt_parse_identifier(p, &method_name)) {
    ok = 0;
  } else {
    const char *type_pkg_use = mbt_pkg_is_core(type_pkg) ? "" : type_pkg;
    if (!mbt_str_append_char(out, '@') ||
        (method_pkg && method_pkg[0] && (!mbt_str_append_cstr(out, method_pkg) ||
                                         !mbt_str_append_char(out, '.')))) {
      ok = 0;
    }
    if (ok && type_pkg_use && type_pkg_use[0]) {
      if (!mbt_str_append_cstr(out, type_pkg_use) ||
          !mbt_str_append_char(out, '.'))
        ok = 0;
    }
  if (ok && (!mbt_str_append_cstr(out, type_name) ||
             !mbt_str_append_cstr(out, "::") ||
             !mbt_str_append_cstr(out, method_name))) {
    ok = 0;
  }
  if (ok && !mbt_parse_fn_suffixes(p, out))
    ok = 0;
  if (ok && (**p == 'G' || **p == 'H')) {
    if (!mbt_parse_type_args(p, out))
      ok = 0;
  }
  if (ok && !mbt_parse_fn_suffixes(p, out))
    ok = 0;
  }
  free(type_pkg);
  free(type_name);
  free(method_pkg);
  free(method_name);
  return ok;
}

static int demangle_tag_T(const char **p, mbt_str *out) {
  return mbt_append_type_path(p, out, 0);
}

static int demangle_tag_L(const char **p, mbt_str *out) {
  int ok = 1;
  if (**p == 'm')
    (*p)++;
  char *ident = NULL;
  if (!mbt_parse_identifier(p, &ident)) {
    ok = 0;
  } else if (**p != 'S') {
    ok = 0;
  } else {
    (*p)++;
    if (!(**p >= '0' && **p <= '9')) {
      ok = 0;
    } else {
      while (**p >= '0' && **p <= '9')
        (*p)++;
      const char *use = ident;
      if (use[0] == '$')
        use++;
      if (!mbt_str_append_char(out, '@') || !mbt_str_append_cstr(out, use)) {
        ok = 0;
      }
    }
  }
  free(ident);
  return ok;
}

static const char *demangle(const char *func_name, char **owned_out) {
  if (!owned_out)
    return func_name;
  *owned_out = NULL;
  if (!func_name)
    return NULL;
  const char *p = func_name;
  if (p[0] == '$')
    p++;
  if (strlen(p) < 3 || p[0] != '_' || p[1] != 'M' || p[2] != '0')
    return func_name;
  p += 3;

  mbt_str out;
  if (!mbt_str_init(&out))
    return func_name;

  int ok = 1;
  char tag = *p;
  if (!tag)
    ok = 0;
  if (ok)
    p++;

  if (ok) {
    switch (tag) {
      case 'F':
        ok = demangle_tag_F(&p, &out);
        break;
      case 'M':
        ok = demangle_tag_M(&p, &out);
        break;
      case 'I':
        ok = demangle_tag_I(&p, &out);
        break;
      case 'E':
        ok = demangle_tag_E(&p, &out);
        break;
      case 'T':
        ok = demangle_tag_T(&p, &out);
        break;
      case 'L':
        ok = demangle_tag_L(&p, &out);
        break;
      default:
        ok = 0;
        break;
    }
  }

  if (ok && *p != '\0') {
    char c = *p;
    if (!(c == '.' || c == '$' || c == '@'))
      ok = 0;
  }

  if (!ok) {
    free(out.buf);
    return func_name;
  }
  *owned_out = mbt_str_release(&out);
  return *owned_out ? *owned_out : func_name;
}

/* TCCBtFunc signature (see vendor/tinycc/libtcc.h):
   int (*)(void *udata, void *pc, const char *file, int line,
           const char* func, const char *msg)
*/
MOONBIT_EXPORT int moonbit_tcc_backtrace(void *udata, void *pc,
                                        const char *file, int line,
                                        const char *func, const char *msg) {
  (void)udata;

  /* Streamed printing (recommended): TinyCC does not provide an explicit
     "end-of-backtrace" callback, so delaying output until we see "main"
     can drop the whole trace if unwinding stops early. */
  if (msg) {
    moonbit__bt_level = 0;
    moonbit__eprint(msg);
    moonbit__eprint("\n");
  }

  if (!func) {
    return 1; /* skip this frame */
  }

  char *owned_name = NULL;
  const char *func_name = demangle(func, &owned_name);

  {
    char linebuf[512];
    size_t len = 0;
    linebuf[0] = 0;

    /* location: either file:line or address */
    if (file) {
      moonbit__bt_buf_append_cstr(linebuf, sizeof linebuf, &len, file);
      moonbit__bt_buf_append_char(linebuf, sizeof linebuf, &len, ':');
      if (line >= 0)
        moonbit__bt_buf_append_u32_dec(linebuf, sizeof linebuf, &len,
                                       (uint32_t)line);
      else
        moonbit__bt_buf_append_cstr(linebuf, sizeof linebuf, &len, "?");
    } else {
      moonbit__bt_buf_append_ptr_hex(linebuf, sizeof linebuf, &len,
                                     (uintptr_t)(const void *)pc);
    }
    moonbit__bt_buf_append_char(linebuf, sizeof linebuf, &len, ' ');

    moonbit__bt_buf_append_cstr(linebuf, sizeof linebuf, &len,
                                (moonbit__bt_level == 0) ? "at" : "by");
    moonbit__bt_buf_append_char(linebuf, sizeof linebuf, &len, ' ');
    moonbit__bt_buf_append_cstr(linebuf, sizeof linebuf, &len, func_name);
    moonbit__bt_buf_append_cstr(linebuf, sizeof linebuf, &len, "\n");
    moonbit__eprint_n(linebuf, len);
  }

  moonbit__bt_level += 1;
  free(owned_name);

  if ((func && 0 == strcmp(func, "main")) ||
      moonbit__bt_level >= (uint32_t)MOONBIT_NATIVE_BT_MAX_FRAMES)
    return 0;
  return 1;
}

MOONBIT_EXPORT void *moonbit_malloc_array(enum moonbit_block_kind kind,
                                          int elem_size_shift, int32_t len) {
  int padding = elem_size_shift < 2 ? 1 : 0;
  struct moonbit_object *obj = (struct moonbit_object *)malloc(
      ((len + padding) << elem_size_shift) + sizeof(struct moonbit_object));
  obj->rc = 1;
  obj->meta = Moonbit_make_array_header(kind, elem_size_shift, len);
  return obj + 1;
}

MOONBIT_EXPORT moonbit_string_t moonbit_make_string_raw(int32_t len) {
  moonbit_string_t result = (moonbit_string_t)moonbit_malloc_array(
    moonbit_BLOCK_KIND_VAL_ARRAY,
    1,
    len
  );
  result[len] = 0;
  return result;
}

MOONBIT_EXPORT moonbit_bytes_t moonbit_make_bytes_raw(int32_t len) {
  moonbit_bytes_t result = (moonbit_bytes_t)moonbit_malloc_array(
    moonbit_BLOCK_KIND_VAL_ARRAY,
    0,
    len
  );
  result[len] = 0;
  return result;
}

MOONBIT_EXPORT moonbit_string_t moonbit_make_string(int32_t len,
                                                    uint16_t value) {
  uint16_t *str =
      (uint16_t *)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY, 1, len);
  for (int32_t i = 0; i < len; ++i) {
    str[i] = value;
  }
  str[len] = 0;
  return str;
}

MOONBIT_EXPORT int moonbit_val_array_equal(const void *lhs, const void *rhs) {
  int32_t const len = Moonbit_array_length(lhs);
  if (len != Moonbit_array_length(rhs))
    return 0;

  int32_t const elem_size = 1 << Moonbit_array_elem_size_shift(lhs);

  return 0 == memcmp(lhs, rhs, len * elem_size);
}

MOONBIT_EXPORT moonbit_string_t moonbit_add_string(moonbit_string_t s1,
                                                   moonbit_string_t s2) {
  int32_t const len1 = Moonbit_array_length(s1);
  int32_t const len2 = Moonbit_array_length(s2);
  moonbit_string_t result = (moonbit_string_t)moonbit_malloc_array(
      moonbit_BLOCK_KIND_VAL_ARRAY, 1, len1 + len2);
  memcpy(result, s1, len1 * 2);
  memcpy(result + len1, s2, len2 * 2);
  result[len1 + len2] = 0;
  return result;
}

MOONBIT_EXPORT moonbit_bytes_t moonbit_make_bytes(int32_t size, int init) {
  moonbit_bytes_t result = (moonbit_bytes_t)moonbit_malloc_array(
      moonbit_BLOCK_KIND_VAL_ARRAY, 0, size);
  memset(result, init, size);
  result[size] = 0;
  return result;
}

MOONBIT_EXPORT void moonbit_unsafe_bytes_blit(moonbit_bytes_t dst,
                                              int32_t dst_start,
                                              moonbit_bytes_t src,
                                              int32_t src_offset, int32_t len) {
  memmove(dst + dst_start, src + src_offset, len);
  moonbit_decref(dst);
  moonbit_decref(src);
}

MOONBIT_EXPORT moonbit_string_t moonbit_unsafe_bytes_sub_string(
    moonbit_bytes_t bytes, int32_t start, int32_t len) {
  int32_t str_len = len / 2 + (len & 1);
  moonbit_string_t str = (moonbit_string_t)moonbit_malloc_array(
      moonbit_BLOCK_KIND_VAL_ARRAY, 1, str_len);
  memcpy(str, bytes + start, len);
  str[str_len] = 0;
  moonbit_decref(bytes);
  return str;
}

MOONBIT_EXPORT void moonbit_println(moonbit_string_t str) {
#ifdef _WIN32
  unsigned int prev_cp = GetConsoleOutputCP();
  SetConsoleOutputCP(CP_UTF8);
#endif
  int32_t const len = Moonbit_array_length(str);
  for (int32_t i = 0; i < len; ++i) {
    uint32_t c = str[i];
    if (0xD800 <= c && c <= 0xDBFF) {
      c -= 0xD800;
      i = i + 1;
      uint32_t l = str[i] - 0xDC00;
      c = ((c << 10) + l) + 0x10000;
    }
    // stdout accepts UTF-8, so convert the stream to UTF-8 first
    if (c < 0x80) {
      putchar(c);
    } else if (c < 0x800) {
      putchar(0xc0 + (c >> 6));
      putchar(0x80 + (c & 0x3f));
    } else if (c < 0x10000) {
      putchar(0xe0 + (c >> 12));
      putchar(0x80 + ((c >> 6) & 0x3f));
      putchar(0x80 + (c & 0x3f));
    } else {
      putchar(0xf0 + (c >> 18));
      putchar(0x80 + ((c >> 12) & 0x3f));
      putchar(0x80 + ((c >> 6) & 0x3f));
      putchar(0x80 + (c & 0x3f));
    }
  }
  putchar('\n');
#ifdef _WIN32
  SetConsoleOutputCP(prev_cp);
#endif
}

MOONBIT_EXPORT int32_t *moonbit_make_int32_array_raw(int32_t len) {
  if (len == 0)
    return moonbit_empty_int32_array;
  return (int32_t *)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY, 2, len);
}

MOONBIT_EXPORT int32_t *moonbit_make_int32_array(int32_t len, int32_t value) {
  int32_t *arr = moonbit_make_int32_array_raw(len);
  for (int32_t i = 0; i < len; ++i) {
    arr[i] = value;
  }
  return arr;
}

MOONBIT_EXPORT void **moonbit_make_ref_array_raw(int32_t len) {
  if (len == 0)
    return moonbit_empty_ref_array;
  return (void **)moonbit_malloc_array(moonbit_BLOCK_KIND_REF_ARRAY,
                                       (sizeof(void *) >> 2) + 1, len);
}

MOONBIT_EXPORT void **moonbit_make_ref_array(int32_t len, void *value) {
  if (len == 0) {
    if (value)
      moonbit_decref(value);
    return moonbit_empty_ref_array;
  }

  void **arr = moonbit_make_ref_array_raw(len);

  if (value) {
    struct moonbit_object *value_header = Moonbit_object_header(value);
    const int32_t count = value_header->rc;
    if (count > 0 && len > 1) {
      value_header->rc = count + len - 1;
    }
  }
  for (int32_t i = 0; i < len; ++i) {
    arr[i] = value;
  }
  return arr;
}

MOONBIT_EXPORT void **moonbit_make_extern_ref_array_raw(int32_t len) {
  if (len == 0)
    return moonbit_empty_extern_ref_array;
  return (void **)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY,
                                       (sizeof(void *) >> 2) + 1, len);
}

MOONBIT_EXPORT void **moonbit_make_extern_ref_array(int32_t len, void *value) {
  void **arr = moonbit_make_extern_ref_array_raw(len);
  for (int32_t i = 0; i < len; ++i) {
    arr[i] = value;
  }
  return arr;
}

MOONBIT_EXPORT int64_t *moonbit_make_int64_array_raw(int32_t len) {
  if (len == 0)
    return moonbit_empty_int64_array;
  return (int64_t *)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY, 3, len);
}

MOONBIT_EXPORT int64_t *moonbit_make_int64_array(int32_t len, int64_t value) {
  int64_t *arr = moonbit_make_int64_array_raw(len);
  for (int32_t i = 0; i < len; ++i) {
    arr[i] = value;
  }
  return arr;
}

MOONBIT_EXPORT double *moonbit_make_double_array_raw(int32_t len) {
  if (len == 0)
    return moonbit_empty_double_array;
  return (double *)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY, 3, len);
}

MOONBIT_EXPORT double *moonbit_make_double_array(int32_t len, double value) {
  double *arr = moonbit_make_double_array_raw(len);
  for (int32_t i = 0; i < len; ++i) {
    arr[i] = value;
  }
  return arr;
}

MOONBIT_EXPORT float *moonbit_make_float_array_raw(int32_t len) {
  if (len == 0)
    return moonbit_empty_float_array;
  return (float *)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY, 2, len);
}

MOONBIT_EXPORT float *moonbit_make_float_array(int32_t len, float value) {
  float *arr = moonbit_make_float_array_raw(len);
  for (int32_t i = 0; i < len; ++i) {
    arr[i] = value;
  }
  return arr;
}

static struct {
  int32_t rc;
  uint32_t meta;
  void *data[];
} moonbit_empty_scalar_valtype_array_object = {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 0, 0)};

MOONBIT_EXPORT void *const moonbit_empty_scalar_valtype_array =
    moonbit_empty_scalar_valtype_array_object.data;

MOONBIT_EXPORT void *moonbit_make_scalar_valtype_array(int32_t len,
                                                       size_t valtype_size,
                                                       void *init) {
  void *array = moonbit_make_scalar_valtype_array_raw(len, valtype_size);
  if (array) {
    for (int32_t i = 0; i < len; ++i) {
      memcpy((uint8_t *)array + i * valtype_size, init, valtype_size);
    }
  }
  return array;
}

MOONBIT_EXPORT void *
moonbit_make_scalar_valtype_array_raw(int32_t len, size_t valtype_size) {
  if (len == 0)
    return moonbit_empty_scalar_valtype_array;
  struct moonbit_object *obj = (struct moonbit_object *)malloc(
      len * valtype_size + sizeof(struct moonbit_object));
  obj->rc = 1;
  obj->meta = Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 0, len);
  return (void *)(obj + 1);
}

static struct {
  int32_t rc;
  uint32_t meta;
  void *data[];
} moonbit_empty_ref_valtype_array_object = {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_REF_ARRAY,
                                  moonbit_REF_ARRAY_REF_VALTYPE, 0)};

MOONBIT_EXPORT void *const moonbit_empty_ref_valtype_array =
    moonbit_empty_ref_valtype_array_object.data;

MOONBIT_EXPORT void moonbit_update_ref_valtype_rc(int32_t len, void *value,
                                                  uint32_t header) {
  const int32_t ptr_field_offset = Moonbit_header_ptr_field_offset(header);
  const int32_t n_ptr_fields = Moonbit_header_ptr_field_count(header);
  void **ptrs = (void **)(((uint32_t *)value) + ptr_field_offset);
  if (len == 0) {
    for (int32_t i = 0; i < n_ptr_fields; ++i) {
      if (ptrs[i])
        moonbit_decref(ptrs[i]);
    }
  } else if (len > 1) {
    for (int32_t i = 0; i < n_ptr_fields; ++i) {
      if (ptrs[i]) {
        struct moonbit_object *value_header = Moonbit_object_header(ptrs[i]);
        const int32_t count = value_header->rc;
        if (count > 0) {
          value_header->rc = count + len - 1;
        }
      }
    }
  }
}

MOONBIT_EXPORT void *moonbit_make_ref_valtype_array(int32_t len,
                                                    size_t valtype_size,
                                                    uint32_t header,
                                                    void *init) {
  void *array = moonbit_make_ref_valtype_array_raw(len, valtype_size, header);
  if (array) {
    for (int32_t i = 0; i < len; ++i) {
      memcpy((uint8_t *)array + i * valtype_size, init, valtype_size);
    }
  }
  return array;
}

MOONBIT_EXPORT void *moonbit_make_ref_valtype_array_raw(int32_t len,
                                                        size_t valtype_size,
                                                        uint32_t header) {
  if (len == 0)
    return moonbit_empty_ref_valtype_array;
  // the extra header is 4-byte but we allocate extra 8-byte for better
  // alignment
  size_t const total_size =
      len * valtype_size + sizeof(struct moonbit_object) + sizeof(void *);
  struct moonbit_object *obj = (struct moonbit_object *)malloc(total_size);
  *(uint64_t *)obj = (uint64_t)header;
  obj = (struct moonbit_object *)(((uint64_t *)obj) + 1);
  obj->rc = 1;
  obj->meta = Moonbit_make_array_header(moonbit_BLOCK_KIND_REF_ARRAY,
                                        moonbit_REF_ARRAY_REF_VALTYPE, len);
  return (void *)(obj + 1);
}

MOONBIT_EXPORT void *moonbit_make_external_object(void (*finalize)(void *self),
                                                  uint32_t payload_size) {
  void *result = moonbit_malloc(sizeof(void (*)(void *)) + payload_size);
  Moonbit_object_header(result)->meta =
      ((uint32_t)moonbit_BLOCK_KIND_EXTERNAL << 30) |
      (payload_size & ((1 << 30) - 1));
  void (**addr_of_finalize)(void *) =
      (void (**)(void *))((uint8_t *)result + payload_size);
  *addr_of_finalize = finalize;
  return result;
}

static struct {
  int32_t rc;
  uint32_t meta;
  uint8_t data[];
} moonbit_empty_int8_array_object = {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 2, 0)};

MOONBIT_EXPORT uint8_t *const moonbit_empty_int8_array =
    moonbit_empty_int8_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  uint16_t data[];
} moonbit_empty_int16_array_object = {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 2, 0)};

MOONBIT_EXPORT uint16_t *const moonbit_empty_int16_array =
    moonbit_empty_int16_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  int32_t data[];
} moonbit_empty_int32_array_object = {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 2, 0)};

MOONBIT_EXPORT int32_t *const moonbit_empty_int32_array =
    moonbit_empty_int32_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  int64_t data[];
} moonbit_empty_int64_array_object = {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 3, 0)};

MOONBIT_EXPORT int64_t *const moonbit_empty_int64_array =
    moonbit_empty_int64_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  float data[];
} moonbit_empty_float_array_object = {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 2, 0)};

MOONBIT_EXPORT float *const moonbit_empty_float_array =
    moonbit_empty_float_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  double data[];
} moonbit_empty_double_array_object = {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 3, 0)};

MOONBIT_EXPORT double *const moonbit_empty_double_array =
    moonbit_empty_double_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  void *data[];
} moonbit_empty_ref_array_object = {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_REF_ARRAY,
                                  (sizeof(void *) >> 2) + 1, 0)};

MOONBIT_EXPORT void **const moonbit_empty_ref_array =
    moonbit_empty_ref_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  void *data[];
} moonbit_empty_extern_ref_array_object = {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY,
                                  (sizeof(void *) >> 2) + 1, 0)};

MOONBIT_EXPORT void **const moonbit_empty_extern_ref_array =
    moonbit_empty_extern_ref_array_object.data;

static int __moonbit_internal_argc = 0;
static char **__moonbit_internal_argv = 0;

MOONBIT_EXPORT moonbit_bytes_t *moonbit_get_cli_args(void) {
  moonbit_bytes_t *result =
      (moonbit_bytes_t *)moonbit_make_ref_array(__moonbit_internal_argc, 0);
  for (int i = 0; i < __moonbit_internal_argc; ++i) {
    int len = strlen(__moonbit_internal_argv[i]);
    moonbit_bytes_t arg = moonbit_make_bytes(len, 0);
    memcpy(arg, __moonbit_internal_argv[i], len);
    result[i] = arg;
  }
  return result;
}

MOONBIT_EXPORT void moonbit_runtime_init(int argc, char **argv) {
  __moonbit_internal_argc = argc;
  __moonbit_internal_argv = argv;
}

#ifndef MOONBIT_NATIVE_NO_SYS_HEADER

#include <errno.h>
#include <sys/stat.h>
#include <time.h>

#ifdef _WIN32
#include <direct.h>
#else
#include <dirent.h>
#include <sys/time.h>
#include <unistd.h>
#endif

/* Environment variable format notes:
   - On Unix/POSIX, `environ` is a NULL-terminated array of byte strings in
     `KEY=VALUE` form. Both key and value are treated as opaque bytes here.
   - On Windows, `GetEnvironmentStringsA` returns a double-NULL-terminated
     block of ANSI strings in `KEY=VALUE` form. Entries that start with '=' are
     pseudo variables (for example `=C:=C:\path`) and are skipped.
   - This runtime intentionally keeps env keys/values as raw bytes; encoding and
     decoding are handled at higher layers.
   - Exported symbol names are namespaced with `moonbit_rt_` to avoid collisions
     with package-local stubs that may define generic names like `get_env_var`.
*/
MOONBIT_EXPORT moonbit_bytes_t moonbit_rt_get_env_var(moonbit_bytes_t key) {
#ifdef _WIN32
  DWORD buf_size = GetEnvironmentVariableA((LPCSTR)key, NULL, 0);
  if (buf_size == 0) {
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t result = moonbit_make_bytes(buf_size - 1, 0);
  GetEnvironmentVariableA((LPCSTR)key, (LPSTR)result, buf_size);
  return result;
#else
  char *value = getenv((const char *)key);
  if (value == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  size_t len = strlen(value);
  moonbit_bytes_t result = moonbit_make_bytes(len, 0);
  memcpy(result, value, len);
  return result;
#endif
}

MOONBIT_EXPORT int32_t moonbit_rt_get_env_var_exists(moonbit_bytes_t key) {
#ifdef _WIN32
  DWORD buf_size = GetEnvironmentVariableA((LPCSTR)key, NULL, 0);
  return buf_size != 0;
#else
  char *value = getenv((const char *)key);
  return value != NULL;
#endif
}

MOONBIT_EXPORT moonbit_bytes_t *moonbit_rt_get_env_vars(void) {
#ifdef _WIN32
  LPCH env_block = GetEnvironmentStringsA();
  if (env_block == NULL) {
    return (moonbit_bytes_t *)moonbit_make_ref_array(0, NULL);
  }

  int count = 0;
  LPCH env = env_block;
  while (*env) {
    char *equals = strchr(env, '=');
    if (env[0] != '=' && equals != NULL && equals != env) {
      count++;
    }
    env += strlen(env) + 1;
  }

  moonbit_bytes_t *result =
      (moonbit_bytes_t *)moonbit_make_ref_array(count * 2, NULL);

  env = env_block;
  int i = 0;
  while (*env) {
    char *equals = strchr(env, '=');
    if (env[0] != '=' && equals != NULL && equals != env) {
      size_t key_len = equals - env;
      size_t val_len = strlen(equals + 1);

      moonbit_bytes_t key_bytes = moonbit_make_bytes(key_len, 0);
      memcpy(key_bytes, env, key_len);

      moonbit_bytes_t value_bytes = moonbit_make_bytes(val_len, 0);
      memcpy(value_bytes, equals + 1, val_len);

      result[i * 2] = key_bytes;
      result[(i * 2) + 1] = value_bytes;
      i++;
    }
    env += strlen(env) + 1;
  }

  FreeEnvironmentStringsA(env_block);
  return result;
#else
  extern char **environ;

  int count = 0;
  char **env = environ;
  while (*env != NULL) {
    count++;
    env++;
  }

  moonbit_bytes_t *result =
      (moonbit_bytes_t *)moonbit_make_ref_array(count * 2, NULL);
  env = environ;
  int i = 0;
  while (*env != NULL) {
    char *equals = strchr(*env, '=');
    if (equals != NULL) {
      size_t key_len = equals - *env;
      size_t val_len = strlen(equals + 1);

      moonbit_bytes_t key_bytes = moonbit_make_bytes(key_len, 0);
      memcpy(key_bytes, *env, key_len);

      moonbit_bytes_t value_bytes = moonbit_make_bytes(val_len, 0);
      memcpy(value_bytes, equals + 1, val_len);

      result[i * 2] = key_bytes;
      result[(i * 2) + 1] = value_bytes;
    }
    env++;
    i++;
  }
  return result;
#endif
}

MOONBIT_EXPORT void moonbit_rt_set_env_var(moonbit_bytes_t key,
                                           moonbit_bytes_t value) {
#ifdef _WIN32
  SetEnvironmentVariableA((LPCSTR)key, (LPCSTR)value);
#else
  setenv((const char *)key, (const char *)value, 1);
#endif
}

MOONBIT_EXPORT void moonbit_rt_unset_env_var(moonbit_bytes_t key) {
#ifdef _WIN32
  SetEnvironmentVariableA((LPCSTR)key, NULL);
#else
  unsetenv((const char *)key);
#endif
}

MOONBIT_EXPORT FILE *moonbit_fopen_ffi(moonbit_bytes_t path,
                                       moonbit_bytes_t mode) {
  return fopen((const char *)path, (const char *)mode);
}

MOONBIT_EXPORT int moonbit_is_null(void *ptr) { return ptr == NULL; }

MOONBIT_EXPORT size_t moonbit_fread_ffi(moonbit_bytes_t ptr, int size,
                                        int nitems, FILE *stream) {
  return fread(ptr, size, nitems, stream);
}

MOONBIT_EXPORT size_t moonbit_fwrite_ffi(moonbit_bytes_t ptr, int size,
                                         int nitems, FILE *stream) {
  return fwrite(ptr, size, nitems, stream);
}

MOONBIT_EXPORT int moonbit_fseek_ffi(FILE *stream, long offset, int whence) {
  return fseek(stream, offset, whence);
}

MOONBIT_EXPORT long moonbit_ftell_ffi(FILE *stream) { return ftell(stream); }

MOONBIT_EXPORT int moonbit_fflush_ffi(FILE *file) { return fflush(file); }

MOONBIT_EXPORT int moonbit_fclose_ffi(FILE *stream) { return fclose(stream); }

MOONBIT_EXPORT moonbit_bytes_t moonbit_get_error_message(void) {
  const char *err_str = strerror(errno);
  size_t len = strlen(err_str);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, err_str, len);
  return bytes;
}

MOONBIT_EXPORT int moonbit_stat_ffi(moonbit_bytes_t path) {
  struct stat buffer;
  int status = stat((const char *)path, &buffer);
  return status;
}

MOONBIT_EXPORT int moonbit_is_dir_ffi(moonbit_bytes_t path) {
#ifdef _WIN32
  DWORD attrs = GetFileAttributes((const char *)path);
  if (attrs == INVALID_FILE_ATTRIBUTES) {
    return -1;
  }
  if (attrs & FILE_ATTRIBUTE_DIRECTORY) {
    return 1;
  }
  return 0;
#else
  struct stat buffer;
  int status = stat((const char *)path, &buffer);
  if (status == -1) {
    return -1;
  }
  if (S_ISDIR(buffer.st_mode)) {
    return 1;
  }
  return 0;
#endif
}

MOONBIT_EXPORT int moonbit_is_file_ffi(moonbit_bytes_t path) {
#ifdef _WIN32
  DWORD attrs = GetFileAttributes((const char *)path);
  if (attrs == INVALID_FILE_ATTRIBUTES) {
    return -1;
  }
  if (!(attrs & FILE_ATTRIBUTE_DIRECTORY)) {
    return 1;
  }
  return 0;
#else
  struct stat buffer;
  int status = stat((const char *)path, &buffer);
  if (status == -1) {
    return -1;
  }
  if (S_ISREG(buffer.st_mode)) {
    return 1;
  }
  return 0;
#endif
}

MOONBIT_EXPORT int moonbit_remove_dir_ffi(moonbit_bytes_t path) {
#ifdef _WIN32
  return _rmdir((const char *)path);
#else
  return rmdir((const char *)path);
#endif
}

MOONBIT_EXPORT int moonbit_remove_file_ffi(moonbit_bytes_t path) {
  return remove((const char *)path);
}

MOONBIT_EXPORT int moonbit_create_dir_ffi(moonbit_bytes_t path) {
#ifdef _WIN32
  return _mkdir((const char *)path);
#else
  return mkdir((const char *)path, 0777);
#endif
}

MOONBIT_EXPORT moonbit_bytes_t *moonbit_read_dir_ffi(moonbit_bytes_t path) {
#ifdef _WIN32
  WIN32_FIND_DATA find_data;
  HANDLE dir;
  moonbit_bytes_t *result = NULL;
  int count = 0;

  size_t path_len = strlen((const char *)path);
  char *search_path = malloc(path_len + 3);
  if (search_path == NULL) {
    return NULL;
  }

  sprintf(search_path, "%s\\*", (const char *)path);
  dir = FindFirstFile(search_path, &find_data);
  if (dir == INVALID_HANDLE_VALUE) {
    DWORD error = GetLastError();
    fprintf(stderr, "Failed to open directory: error code %lu\n", error);
    free(search_path);
    return NULL;
  }

  do {
    if (find_data.cFileName[0] != '.') {
      count++;
    }
  } while (FindNextFile(dir, &find_data));

  FindClose(dir);
  dir = FindFirstFile(search_path, &find_data);
  free(search_path);

  result = (moonbit_bytes_t *)moonbit_make_ref_array(count, NULL);
  if (result == NULL) {
    FindClose(dir);
    return NULL;
  }

  int index = 0;
  do {
    if (find_data.cFileName[0] != '.') {
      size_t name_len = strlen(find_data.cFileName);
      moonbit_bytes_t item = moonbit_make_bytes(name_len, 0);
      memcpy(item, find_data.cFileName, name_len);
      result[index++] = item;
    }
  } while (FindNextFile(dir, &find_data));

  FindClose(dir);
  return result;
#else

  DIR *dir;
  struct dirent *entry;
  moonbit_bytes_t *result = NULL;
  int count = 0;

  // open the directory
  dir = opendir((const char *)path);
  if (dir == NULL) {
    perror("opendir");
    return NULL;
  }

  // first traversal of the directory, calculate the number of items
  while ((entry = readdir(dir)) != NULL) {
    // ignore hidden files and current/parent directories
    if (entry->d_name[0] != '.') {
      count++;
    }
  }

  // reset the directory stream
  rewinddir(dir);

  // create moonbit_ref_array to store the result
  result = (moonbit_bytes_t *)moonbit_make_ref_array(count, NULL);
  if (result == NULL) {
    closedir(dir);
    return NULL;
  }

  // second traversal of the directory, fill the array
  int index = 0;
  while ((entry = readdir(dir)) != NULL) {
    if (entry->d_name[0] != '.') {
      size_t name_len = strlen(entry->d_name);
      moonbit_bytes_t item = moonbit_make_bytes(name_len, 0);
      memcpy(item, entry->d_name, name_len);
      result[index++] = item;
    }
  }

  closedir(dir);
  return result;
#endif
}

static void timestamp_finalizer(void *dummy) { (void)dummy; }

#ifdef __APPLE__
#define MOONBIT_CLOCK_MONOTONIC CLOCK_MONOTONIC_RAW
#else
#define MOONBIT_CLOCK_MONOTONIC CLOCK_MONOTONIC
#endif

#ifdef _WIN32

struct timestamp {
  LARGE_INTEGER ts;
};

MOONBIT_EXPORT void *moonbit_monotonic_clock_start(void) {
  struct timestamp *ts = moonbit_make_external_object(timestamp_finalizer,
                                                      sizeof(struct timestamp));
  QueryPerformanceCounter(&ts->ts);
  return ts;
}

MOONBIT_EXPORT double moonbit_monotonic_clock_stop(void *prev) {
  LARGE_INTEGER counter;
  (void)QueryPerformanceCounter(&counter);

  static LARGE_INTEGER freq;
  if (freq.QuadPart == 0) // initialize only once
    (void)QueryPerformanceFrequency(&freq);

  struct timestamp *ts = (struct timestamp *)prev;
  return (double)((counter.QuadPart - ts->ts.QuadPart) * 1000000) /
         freq.QuadPart;
}

#else

struct timestamp {
  struct timespec ts;
};

MOONBIT_EXPORT void *moonbit_monotonic_clock_start(void) {
  struct timestamp *ts = moonbit_make_external_object(timestamp_finalizer,
                                                      sizeof(struct timestamp));
  if (0 == clock_gettime(MOONBIT_CLOCK_MONOTONIC, &ts->ts))
    return ts;
  memset(ts, 0, sizeof(struct timestamp));
  return ts;
}

MOONBIT_EXPORT double moonbit_monotonic_clock_stop(void *prev) {
  struct timespec ts;
  if (0 != clock_gettime(MOONBIT_CLOCK_MONOTONIC, &ts))
    return NAN;
  struct timespec *ts0 = &(((struct timestamp *)prev)->ts);
  return (double)((ts.tv_sec - ts0->tv_sec) * 1000000) +
         (double)(ts.tv_nsec - ts0->tv_nsec) / 1000.0;
}

#endif

#endif

#ifdef __cplusplus
}
#endif
