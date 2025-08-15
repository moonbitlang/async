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
void *malloc(size_t size);
void free(void *ptr);
void *memset(void *dst, int c, size_t n);
void *memcpy(void *dst, const void *src, size_t n);
void *memmove(void *dst, const void *src, size_t n);
size_t strlen(const char *s);
int memcmp(const void *s1, const void *s2, size_t n);
_Noreturn void exit(int status);
_Noreturn void abort(void);

#else

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#endif

// header manipulation macros
#define Moonbit_object_ptr_field_offset(obj)\
  ((Moonbit_object_header(obj)->meta >> 19) & (((uint32_t)1 << 11) - 1))

#define Moonbit_object_ptr_field_count(obj)\
  ((Moonbit_object_header(obj)->meta >> 8) & (((uint32_t)1 << 11) - 1))

MOONBIT_EXPORT void *libc_malloc(size_t size) {
  return malloc(size);
}
MOONBIT_EXPORT void libc_free(void *ptr) {
  free(ptr);
}

MOONBIT_EXPORT void *moonbit_malloc(size_t size) {
  struct moonbit_object *ptr = (struct moonbit_object *)malloc(sizeof(struct moonbit_object) + size);
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
     we can *reuse the memory of to-be-dropped objects* to store traversal state.

     Everytime we dive down into a child, we need to remember the following states:

     - our position in the middle of current object (`int32_t`)
     - how many objects remaining in current object (`int32_t`)
     - the parent of current object (`void*`)

     Fortunately, we have exactly the space required in to-be-dropped current object:

     - current position is stored in the `(struct moonbit_object).rc` field
     - remaining children count is stored in the `(struct moonbit_object).meta` field
     - parent is stored in the place where current visited object was previously stored

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

     `curr_child_offset` and `remaining_children_count`, are used by `process_children`.
     So they must be valid before entering `process_children`
  */
  void *parent = 0;
  int32_t curr_child_offset, remaining_children_count;
handle_new_object:
  /* If current object has any children, jump to `process_children`,
     otherwise, we have finished processing current object, fallthrough to `back_to_parent`.
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
        if (elem_size == 0) {
          // view array
          for (int32_t i = 0; i < len; ++i) {
            void *buf = ((struct moonbit_view_t*)obj)[i].buf;
            if (buf) moonbit_decref(buf);
          }
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
      void (**addr_of_finalize)(void*) = (void (**)(void*))((uint8_t*)obj + payload_size);
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
  parent = *(void**)((uint32_t*)parent + curr_child_offset);
  // We have finished processing one object, so move forward by one slot
  curr_child_offset += sizeof(void*) >> 2;
  // Fallthrough to `process_children`, resuming handling of parent

process_children:
  // `curr_child_offset` and `remaining_children_count` must be properly set here.
  while (remaining_children_count > 0) {
    void *next = *(void**)((uint32_t*)obj + curr_child_offset);
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
          *(void**)((uint32_t*)obj + curr_child_offset) = parent;
          parent = obj;
        }
        obj = next;
        goto handle_new_object;
      }
    }
    curr_child_offset += sizeof(void*) >> 2;
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

#ifdef __MACH__
#include <execinfo.h>
#endif

MOONBIT_EXPORT void moonbit_panic(void) {
#ifdef MOONBIT_NATIVE_EXIT_ON_PANIC
  exit(1);
#else
#ifdef __MACH__
  void *trace[10];
  int size = backtrace(trace, 10);
  char **trace_symbols = backtrace_symbols(trace, size);
  for (int i = 0; i < size; ++i)
    printf("%s\n", trace_symbols[i]);
  free(trace_symbols);
#endif
  abort();
#endif
}

MOONBIT_EXPORT void *moonbit_malloc_array(enum moonbit_block_kind kind, int elem_size_shift, int32_t len) {
  int padding = elem_size_shift < 2 ? 1 : 0;
  struct moonbit_object *obj = (struct moonbit_object *)malloc(
    ((len + padding) << elem_size_shift) + sizeof(struct moonbit_object)
  );
  obj->rc = 1;
  obj->meta = Moonbit_make_array_header(kind, elem_size_shift, len);
  return obj + 1;
}

MOONBIT_EXPORT moonbit_string_t moonbit_make_string(int32_t len, uint16_t value) {
  uint16_t *str = (uint16_t*)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY, 1, len);
  for (int32_t i = 0; i < len; ++i) {
    str[i] = value;
  }
  str[len] = 0;
  return str;
}

MOONBIT_EXPORT int moonbit_val_array_equal(const void *lhs, const void *rhs) {
  int32_t const len = Moonbit_array_length(lhs);
  if (len != Moonbit_array_length(rhs)) return 0;

  int32_t const elem_size = 1 << Moonbit_array_elem_size_shift(lhs);

  return 0 == memcmp(lhs, rhs, len * elem_size);
}

MOONBIT_EXPORT moonbit_string_t moonbit_add_string(moonbit_string_t s1, moonbit_string_t s2) {
  int32_t const len1 = Moonbit_array_length(s1);
  int32_t const len2 = Moonbit_array_length(s2);
  moonbit_string_t result = (moonbit_string_t)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY, 1, len1 + len2);
  memcpy(result, s1, len1 * 2);
  memcpy(result + len1, s2, len2 * 2);
  result[len1 + len2] = 0;
  moonbit_decref(s1);
  moonbit_decref(s2);
  return result;
}

MOONBIT_EXPORT moonbit_bytes_t moonbit_make_bytes(int32_t size, int init) {
  moonbit_bytes_t result = (moonbit_bytes_t)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY, 0, size);
  memset(result, init, size);
  result[size] = 0;
  return result;
}

MOONBIT_EXPORT void moonbit_unsafe_bytes_blit(moonbit_bytes_t dst, int32_t dst_start, moonbit_bytes_t src, int32_t src_offset, int32_t len) {
  memmove(dst + dst_start, src + src_offset, len);
  moonbit_decref(dst);
  moonbit_decref(src);
}

MOONBIT_EXPORT moonbit_string_t moonbit_unsafe_bytes_sub_string(moonbit_bytes_t bytes, int32_t start, int32_t len) {
  int32_t str_len = len / 2 + (len & 1);
  moonbit_string_t str = (moonbit_string_t)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY, 1, str_len);
  memcpy(str, bytes + start, len);
  str[str_len] = 0;
  moonbit_decref(bytes);
  return str;
}

#ifdef _WIN32
#include <windows.h>
#endif

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

MOONBIT_EXPORT int32_t *moonbit_make_int32_array(int32_t len, int32_t value) {
  if (len == 0) return moonbit_empty_int32_array;
  int32_t *arr = (int32_t*)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY, 2, len);
  for (int32_t i = 0; i < len; ++i) {
    arr[i] = value;
  }
  return arr;
}

MOONBIT_EXPORT void **moonbit_make_ref_array(int32_t len, void *value) {
  if (len == 0) {
    if (value) moonbit_decref(value);
    return moonbit_empty_ref_array;
  }

  void **arr = (void**)moonbit_malloc_array(moonbit_BLOCK_KIND_REF_ARRAY, (sizeof(void*) >> 2) + 1, len);
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

MOONBIT_EXPORT void *moonbit_make_view_array(int32_t len, void *ptr) {
  struct moonbit_view_t *value = (struct moonbit_view_t *)ptr;
  if (len == 0) {
    // Bor stringview/bytesview, we don't need to check whether
    // buf is null. But it's needed for the arrayview case.
    if (value->buf) moonbit_decref(value->buf);
    return moonbit_empty_view_array;
  }

  // malloc space for the array and the object header
  struct moonbit_object *obj = (struct moonbit_object *)malloc((len * sizeof(struct moonbit_view_t)) + sizeof(struct moonbit_object));
  obj->rc = 1;
  obj->meta = Moonbit_make_array_header(moonbit_BLOCK_KIND_REF_ARRAY, 0, len);
  struct moonbit_view_t *arr = (struct moonbit_view_t *)(obj + 1);

  if (value->buf) {
    struct moonbit_object *value_header = Moonbit_object_header(value->buf);
    const int32_t count = value_header->rc;
    if (count > 0 && len > 1) {
      value_header->rc = count + len - 1;
    }
  }
  for (int32_t i = 0; i < len; ++i) {
    arr[i] = *value;
  }
  return (void*)arr;
}

MOONBIT_EXPORT void **moonbit_make_extern_ref_array(int32_t len, void *value) {
  if (len == 0) return moonbit_empty_extern_ref_array;
  void **arr = (void**)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY, (sizeof(void*) >> 2) + 1, len);
  for (int32_t i = 0; i < len; ++i) {
    arr[i] = value;
  }
  return arr;
}

MOONBIT_EXPORT int64_t *moonbit_make_int64_array(int32_t len, int64_t value) {
  if (len == 0) return moonbit_empty_int64_array;
  int64_t *arr = (int64_t*)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY, 3, len);
  for (int32_t i = 0; i < len; ++i) {
    arr[i] = value;
  }
  return arr;
}

MOONBIT_EXPORT double *moonbit_make_double_array(int32_t len, double value) {
  if (len == 0) return moonbit_empty_double_array;
  double *arr = (double*)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY, 3, len);
  for (int32_t i = 0; i < len; ++i) {
    arr[i] = value;
  }
  return arr;
}

MOONBIT_EXPORT float *moonbit_make_float_array(int32_t len, float value) {
  if (len == 0) return moonbit_empty_float_array;
  float *arr = (float*)moonbit_malloc_array(moonbit_BLOCK_KIND_VAL_ARRAY, 2, len);
  for (int32_t i = 0; i < len; ++i) {
    arr[i] = value;
  }
  return arr;
}

static struct {
  int32_t rc;
  uint32_t meta;
  void* data[];
} moonbit_empty_valtype_array_object = {
  -1,
  Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 0, 0)
};

MOONBIT_EXPORT void *const moonbit_empty_valtype_array = moonbit_empty_valtype_array_object.data;

MOONBIT_EXPORT void *moonbit_make_all_scalar_valtype_array(int32_t len, size_t valtype_size) {
  if (len == 0) return moonbit_empty_valtype_array;
  struct moonbit_object *obj = (struct moonbit_object *)malloc(len * valtype_size + sizeof(struct moonbit_object));
  obj->rc = 1;
  obj->meta = Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 0, len);
  return (void*)(obj + 1);
}

MOONBIT_EXPORT void *moonbit_make_external_object(
  void (*finalize)(void *self),
  uint32_t payload_size
) {
  void *result = moonbit_malloc(sizeof(void(*)(void*)) + payload_size);
  Moonbit_object_header(result)->meta
  = ((uint32_t)moonbit_BLOCK_KIND_EXTERNAL << 30)
    | (payload_size & ((1 << 30) - 1));
  void (**addr_of_finalize)(void*) = (void(**)(void*))((uint8_t*)result + payload_size);
  *addr_of_finalize = finalize;
  return result;
}

static struct {
  int32_t rc;
  uint32_t meta;
  uint8_t data[];
} moonbit_empty_int8_array_object = {
  -1,
  Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 2, 0)
};

MOONBIT_EXPORT uint8_t* const moonbit_empty_int8_array = moonbit_empty_int8_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  uint16_t data[];
} moonbit_empty_int16_array_object = {
  -1,
  Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 2, 0)
};

MOONBIT_EXPORT uint16_t* const moonbit_empty_int16_array = moonbit_empty_int16_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  int32_t data[];
} moonbit_empty_int32_array_object = {
  -1,
  Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 2, 0)
};

MOONBIT_EXPORT int32_t* const moonbit_empty_int32_array = moonbit_empty_int32_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  int64_t data[];
} moonbit_empty_int64_array_object = {
  -1,
  Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 3, 0)
};

MOONBIT_EXPORT int64_t* const moonbit_empty_int64_array = moonbit_empty_int64_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  float data[];
} moonbit_empty_float_array_object = {
  -1,
  Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 2, 0)
};

MOONBIT_EXPORT float* const moonbit_empty_float_array = moonbit_empty_float_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  double data[];
} moonbit_empty_double_array_object = {
  -1,
  Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 3, 0)
};

MOONBIT_EXPORT double* const moonbit_empty_double_array = moonbit_empty_double_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  void* data[];
} moonbit_empty_ref_array_object = {
  -1,
  Moonbit_make_array_header(
    moonbit_BLOCK_KIND_REF_ARRAY,
    (sizeof(void*) >> 2) + 1,
    0
  )
};

MOONBIT_EXPORT void** const moonbit_empty_ref_array = moonbit_empty_ref_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  struct moonbit_view_t data[];
} moonbit_empty_view_array_object = {
  -1,
  Moonbit_make_array_header(
    moonbit_BLOCK_KIND_REF_ARRAY,
    0,
    0
  )
};

MOONBIT_EXPORT struct moonbit_view_t* const moonbit_empty_view_array = moonbit_empty_view_array_object.data;

static struct {
  int32_t rc;
  uint32_t meta;
  void* data[];
} moonbit_empty_extern_ref_array_object = {
  -1,
  Moonbit_make_array_header(
    moonbit_BLOCK_KIND_VAL_ARRAY,
    (sizeof(void*) >> 2) + 1,
    0
  )
};

MOONBIT_EXPORT void** const moonbit_empty_extern_ref_array = moonbit_empty_extern_ref_array_object.data;


static int __moonbit_internal_argc = 0;
static char **__moonbit_internal_argv = 0;

MOONBIT_EXPORT moonbit_bytes_t *moonbit_get_cli_args(void) {
  moonbit_bytes_t *result = (moonbit_bytes_t*)moonbit_make_ref_array(__moonbit_internal_argc, 0);
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
#include <unistd.h>
#include <sys/time.h>
#endif

MOONBIT_EXPORT FILE* moonbit_fopen_ffi(moonbit_bytes_t path, moonbit_bytes_t mode) {
    return fopen((const char*)path, (const char*)mode);
}

MOONBIT_EXPORT int moonbit_is_null(void* ptr) {
    return ptr == NULL;
}

MOONBIT_EXPORT size_t moonbit_fread_ffi(moonbit_bytes_t ptr, int size, int nitems, FILE* stream) {
    return fread(ptr, size, nitems, stream);
}

MOONBIT_EXPORT size_t moonbit_fwrite_ffi(moonbit_bytes_t ptr, int size, int nitems, FILE* stream) {
    return fwrite(ptr, size, nitems, stream);
}

MOONBIT_EXPORT int moonbit_fseek_ffi(FILE* stream, long offset, int whence) {
    return fseek(stream, offset, whence);
}

MOONBIT_EXPORT long moonbit_ftell_ffi(FILE* stream) {
    return ftell(stream);
}

MOONBIT_EXPORT int moonbit_fflush_ffi(FILE* file) {
    return fflush(file);
}

MOONBIT_EXPORT int moonbit_fclose_ffi(FILE* stream) {
    return fclose(stream);
}

MOONBIT_EXPORT moonbit_bytes_t moonbit_get_error_message(void) {
    const char* err_str = strerror(errno);
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
    DWORD attrs = GetFileAttributes((const char*)path);
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
    DWORD attrs = GetFileAttributes((const char*)path);
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
    
    size_t path_len = strlen((const char*)path);
    char* search_path = malloc(path_len + 3);
    if (search_path == NULL) {
        return NULL;
    }
    
    sprintf(search_path, "%s\\*", (const char*)path);
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

    result = (moonbit_bytes_t*)moonbit_make_ref_array(count, NULL);
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
    result = (moonbit_bytes_t*)moonbit_make_ref_array(count, NULL);
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

static void timestamp_finalizer(void *dummy) {
  (void)dummy;
}

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
  struct timestamp *ts = moonbit_make_external_object(timestamp_finalizer, sizeof(struct timestamp));
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
  return (double)((counter.QuadPart - ts->ts.QuadPart) * 1000000) / freq.QuadPart;
}

#else

struct timestamp {
  struct timespec ts;
};

MOONBIT_EXPORT void *moonbit_monotonic_clock_start(void) {
  struct timestamp *ts = moonbit_make_external_object(timestamp_finalizer, sizeof(struct timestamp));
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
