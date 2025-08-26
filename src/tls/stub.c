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

#include <dlfcn.h>
#include <string.h>
#include <moonbit.h>

// TODO: are these stable?
#define BIO_TYPE_NONE 0
#define SSL_VERIFY_NONE 0x00
#define SSL_VERIFY_PEER 0x01
#define BIO_CTRL_FLUSH 11
#define SSL_CTRL_MODE 33
#define SSL_MODE_ENABLE_PARTIAL_WRITE 0x00000001U

typedef struct BIO_METHOD BIO_METHOD;
typedef struct BIO BIO;
typedef struct SSL SSL;
typedef struct SSL_CTX SSL_CTX;
typedef struct SSL_METHOD SSL_METHOD;

#define IMPORTED_OPEN_SSL_FUNCTIONS\
  IMPORT_FUNC(BIO_METHOD*, BIO_meth_new, (int type, const char *name))\
  IMPORT_FUNC(int, BIO_meth_set_write, (BIO_METHOD *biom, int (*write)(BIO *, const void *, int)))\
  IMPORT_FUNC(int, BIO_meth_set_read, (BIO_METHOD *biom, int (*read)(BIO *, void *, int)))\
  IMPORT_FUNC(int, BIO_meth_set_ctrl, (BIO_METHOD *biom, long (*ctrl)(BIO *, int, long, void *)))\
  IMPORT_FUNC(int, BIO_meth_set_destroy, (BIO_METHOD *biom, int (*destroy)(BIO *)))\
  IMPORT_FUNC(BIO *, BIO_new, (const BIO_METHOD *type))\
  IMPORT_FUNC(void, BIO_set_data, (BIO *bio, void *data))\
  IMPORT_FUNC(void *, BIO_get_data, (BIO *bio))\
  IMPORT_FUNC(void, BIO_set_init, (BIO *bio, int init))\
  IMPORT_FUNC(void, BIO_set_flags, (BIO *bio, int flags))\
  IMPORT_FUNC(void, BIO_set_shutdown, (BIO *bio, int shutdown))\
  IMPORT_FUNC(SSL *, SSL_new, (SSL_CTX *ctx))\
  IMPORT_FUNC(void, SSL_set_bio, (SSL *s, BIO *rbio, BIO *wbio))\
  IMPORT_FUNC(int, SSL_connect, (SSL *ssl))\
  IMPORT_FUNC(void, SSL_set_verify, (SSL *ssl, int mode, int (*verify_cb)(int, void*)))\
  IMPORT_FUNC(int, SSL_accept, (SSL *ssl))\
  IMPORT_FUNC(int, SSL_use_certificate_file, (SSL *ssl, const char *file, int type))\
  IMPORT_FUNC(int, SSL_use_PrivateKey_file, (SSL *ssl, const char *file, int type))\
  IMPORT_FUNC(int, SSL_read, (SSL *ssl, void *buf, int num))\
  IMPORT_FUNC(int, SSL_write, (SSL *ssl, void *buf, int num))\
  IMPORT_FUNC(int, SSL_get_error, (SSL *ssl, int ret))\
  IMPORT_FUNC(int, SSL_shutdown, (SSL *ssl))\
  IMPORT_FUNC(void, SSL_free, (SSL *ssl))\
  IMPORT_FUNC(SSL_CTX *, SSL_CTX_new, (const SSL_METHOD*))\
  IMPORT_FUNC(void, SSL_CTX_free, (SSL_CTX *))\
  IMPORT_FUNC(SSL_METHOD *, TLS_client_method, (void))\
  IMPORT_FUNC(SSL_METHOD *, TLS_server_method, (void))\
  IMPORT_FUNC(long, SSL_CTX_ctrl, (SSL_CTX *ctx, int cmd, long larg, void *parg))\
  IMPORT_FUNC(void, SSL_CTX_set_verify, (SSL_CTX *ctx, int mode, int (*verify_cb)(int, void*)))\
  IMPORT_FUNC(int, SSL_CTX_set_default_verify_paths, (SSL_CTX *ctx))\
  IMPORT_FUNC(unsigned long, ERR_get_error, (void))\
  IMPORT_FUNC(char *, ERR_error_string, (unsigned long e, char *buf))\

#define IMPORT_FUNC(ret, name, params) static ret (*name) params;
IMPORTED_OPEN_SSL_FUNCTIONS
#undef IMPORT_FUNC

int moonbitlang_async_load_openssl(int *major, int *minor, int *fix) {
  void *handle = 0;

#ifdef __MACH__
  handle = dlopen("/usr/lib/libssl.48.dylib", RTLD_LAZY);
  if (!handle) handle = dlopen("/usr/lib/libssl.46.dylib", RTLD_LAZY);
#else
  handle = dlopen("libssl.so.3", RTLD_LAZY);
  if (!handle) handle = dlopen("libssl.so.1.1", RTLD_LAZY);
  if (!handle) handle = dlopen("libssl.so", RTLD_LAZY);
#endif
  if (!handle) return 1;

  unsigned long (*OPENSSL_version_num)() = dlsym(handle, "OpenSSL_version_num");
  if (!OPENSSL_version_num)
    return 2;

  unsigned long version = (*OPENSSL_version_num)();
  *major = version >> 28;
  *minor = (version >> 20) & 0xff;
  *fix = (version >> 12) & 0xff;

  if (*major < 1 || *major == 1 && (*minor < 1 || *minor == 1 && *fix < 1))
    return 3;

#define IMPORT_FUNC(ret, func, params)\
  func = dlsym(handle, "" #func "");\
  if (!func) return 4;

  IMPORTED_OPEN_SSL_FUNCTIONS

#undef LOAD_FUNC

  return 0;
}

void *moonbitlang_async_tls_bio_get_endpoint(BIO * bio) {
  return BIO_get_data(bio);
}

void moonbitlang_async_tls_bio_set_flags(BIO * bio, int flags) {
  return BIO_set_flags(bio, flags);
}

void moonbitlang_async_tls_bio_set_shutdown(BIO * bio, int flags) {
  return BIO_set_flags(bio, flags);
}

static
int apply_read_closure(BIO *bio, void *buf, int num) {
  void *closure = BIO_get_data(bio);
  int (*read)(void *self, void *buf, int num) = *((int (**)(void *, void *, int))closure);
  moonbit_incref(closure);
  return read(closure, buf, num);
}

static
int apply_write_closure(BIO *bio, const void *buf, int num) {
  void *closure = BIO_get_data(bio);
  int (*write)(void *self, const void *buf, int num) = *((int (**)(void *, const void *, int))closure);
  moonbit_incref(closure);
  return write(closure, buf, num);
}

static
long dummy_bio_ctrl(BIO *bio, int cmd, long larg, void *parg) {
  if (cmd == BIO_CTRL_FLUSH) {
    // BIO_CTRL_FLUSH, this is required by SSL
    return 1;
  } else {
    return 0;
  }
}

static
int destroy_closure_bio(BIO *bio) {
  moonbit_decref(BIO_get_data(bio));
  return 1;
}

BIO *moonbitlang_async_tls_create_rbio(
  void *data,
  int (*read)(BIO *, void *, int)
) {
  BIO_METHOD *biom = BIO_meth_new(BIO_TYPE_NONE, "moonbitlang/async");
  BIO_meth_set_read(biom, read);
  BIO_meth_set_ctrl(biom, dummy_bio_ctrl);
  BIO_meth_set_destroy(biom, destroy_closure_bio);

  BIO *bio = BIO_new(biom);
  BIO_set_data(bio, data);
  BIO_set_init(bio, 1);
  return bio;
}

BIO *moonbitlang_async_tls_create_wbio(
  void *data,
  int (*write)(BIO *, const void *, int)
) {
  BIO_METHOD *biom = BIO_meth_new(BIO_TYPE_NONE, "moonbitlang/async");
  BIO_meth_set_write(biom, write);
  BIO_meth_set_ctrl(biom, dummy_bio_ctrl);
  BIO_meth_set_destroy(biom, destroy_closure_bio);

  BIO *bio = BIO_new(biom);
  BIO_set_data(bio, data);
  BIO_set_init(bio, 1);
  return bio;
}

int moonbitlang_async_tls_ssl_ctx_is_null(SSL_CTX *ctx) {
  return ctx == 0;
}

SSL_CTX *moonbitlang_async_tls_client_ctx() {
  SSL_CTX *client_ctx = SSL_CTX_new(TLS_client_method());

  SSL_CTX_set_verify(client_ctx, SSL_VERIFY_PEER, 0);
  if (!SSL_CTX_set_default_verify_paths(client_ctx)) {
    SSL_CTX_free(client_ctx);
    return 0;
  }

  SSL_CTX_ctrl(client_ctx, SSL_CTRL_MODE, SSL_MODE_ENABLE_PARTIAL_WRITE, 0);
  return client_ctx;
}

SSL_CTX *moonbitlang_async_tls_server_ctx() {
  SSL_CTX *server_ctx = SSL_CTX_new(TLS_server_method());
  SSL_CTX_ctrl(server_ctx, SSL_CTRL_MODE, SSL_MODE_ENABLE_PARTIAL_WRITE, 0);
  return server_ctx;
}

SSL *moonbitlang_async_tls_ssl_new(SSL_CTX *ctx, BIO *rbio, BIO *wbio) {
  SSL *ssl = SSL_new(ctx);
  if (!ssl) return ssl;

  SSL_set_bio(ssl, rbio, wbio);
  return ssl;
}

int moonbitlang_async_tls_ssl_connect(SSL *ssl) {
  return SSL_connect(ssl);
}

void moonbitlang_async_tls_ssl_set_verify(SSL *ssl, int verify) {
  SSL_set_verify(ssl, verify ? SSL_VERIFY_PEER : SSL_VERIFY_NONE, 0);
}

int moonbitlang_async_tls_ssl_accept(SSL *ssl) {
  return SSL_accept(ssl);
}

int moonbitlang_async_tls_ssl_use_certificate_file(
  SSL *ssl,
  const char *file,
  int type
) {
  return SSL_use_certificate_file(ssl, file, type);
}

int moonbitlang_async_tls_ssl_use_private_key_file(
  SSL *ssl,
  const char *file,
  int type
) {
  return SSL_use_PrivateKey_file(ssl, file, type);
}

int moonbitlang_async_tls_ssl_read(SSL *ssl, char *buf, int offset, int num) {
  return SSL_read(ssl, buf + offset, num);
}

int moonbitlang_async_tls_ssl_write(SSL *ssl, char *buf, int offset, int num) {
  return SSL_write(ssl, buf + offset, num);
}

int moonbitlang_async_tls_ssl_shutdown(SSL *ssl) {
  return SSL_shutdown(ssl);
}

void moonbitlang_async_tls_ssl_free(SSL *ssl) {
  SSL_free(ssl);
}

int moonbitlang_async_tls_ssl_get_error(SSL *ssl, int ret) {
  return SSL_get_error(ssl, ret);
}

moonbit_string_t moonbitlang_async_tls_get_error() {
  unsigned long code = ERR_get_error();
  moonbit_bytes_t buf = moonbit_make_bytes(256, 0);
  ERR_error_string(code, buf);
  int len = strlen(buf);
  moonbit_string_t result = moonbit_make_string(len, 0);
  for (int i = 0; i < len; ++i) {
    result[i] = buf[i];
  }
  moonbit_decref(buf);
  return result;
}

void moonbitlang_async_blit_to_c(char *src, char *dst, int offset, int len) {
  memcpy(dst, src + offset, len);
}

void moonbitlang_async_blit_from_c(char *src, char *dst, int offset, int len) {
  memcpy(dst + offset, src, len);
}
