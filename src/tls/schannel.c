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

#ifdef _WIN32

#include <stdint.h>
#include <windows.h>
#include <bcrypt.h>

// https://learn.microsoft.com/en-us/windows/win32/api/schannel/ns-schannel-sch_credentials
#include <SubAuth.h>
#define SCHANNEL_USE_BLACKLISTS
#include <schannel.h>

#define SECURITY_WIN32
#include <security.h>

#include <moonbit.h>

#pragma comment (lib, "secur32.lib")
#pragma comment (lib, "Crypt32.lib")
#pragma comment (lib, "Bcrypt.lib")

struct Context {
  enum {
    Uninitialized,
    HandleInitialized,
    ContextInitialized
  } state;
  CredHandle handle;
  CtxtHandle context;
  ULONG context_attrs;
  int32_t bytes_read;
  int32_t bytes_to_write;
  int32_t msg_trailer;
  SecPkgContext_StreamSizes stream_sizes;
  HCERTSTORE custom_root_store;
  HCERTCHAINENGINE custom_root_chain_engine;
};

MOONBIT_FFI_EXPORT
void moonbitlang_async_schannel_free(struct Context *ctx) {
  if (ctx->custom_root_chain_engine)
    CertFreeCertificateChainEngine(ctx->custom_root_chain_engine);
  if (ctx->custom_root_store)
    CertCloseStore(ctx->custom_root_store, 0);
  switch (ctx->state) {
    case ContextInitialized:
      DeleteSecurityContext(&ctx->context);
    case HandleInitialized:
      FreeCredentialsHandle(&ctx->handle);
    case Uninitialized:
      break;
  }
  free(ctx);
}

MOONBIT_FFI_EXPORT
struct Context *moonbitlang_async_schannel_new() {
  struct Context *result = (struct Context*)malloc(sizeof(struct Context));
  result->state = Uninitialized;
  result->context.dwUpper = 0;
  result->context.dwLower = 0;
  result->custom_root_store = 0;
  result->custom_root_chain_engine = 0;
  return result;
}

static
HCERTSTORE get_or_create_custom_root_store(struct Context *ctx) {
  if (ctx->custom_root_store)
    return ctx->custom_root_store;

  ctx->custom_root_store = CertOpenStore(
    CERT_STORE_PROV_MEMORY,
    0,
    0,
    CERT_STORE_CREATE_NEW_FLAG,
    NULL
  );
  return ctx->custom_root_store;
}

static
HCERTCHAINENGINE get_or_create_custom_root_chain_engine(struct Context *ctx) {
  if (ctx->custom_root_chain_engine)
    return ctx->custom_root_chain_engine;

  CERT_CHAIN_ENGINE_CONFIG config;
  memset(&config, 0, sizeof(CERT_CHAIN_ENGINE_CONFIG));
  config.cbSize = sizeof(CERT_CHAIN_ENGINE_CONFIG);
  config.hExclusiveRoot = ctx->custom_root_store;
  config.dwExclusiveFlags = CERT_CHAIN_EXCLUSIVE_ENABLE_CA_FLAG;

  if (!CertCreateCertificateChainEngine(&config, &ctx->custom_root_chain_engine))
    return 0;

  return ctx->custom_root_chain_engine;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_bytes_read(struct Context *ctx) {
  return ctx->bytes_read;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_bytes_to_write(struct Context *ctx) {
  return ctx->bytes_to_write;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_msg_trailer(struct Context *ctx) {
  return ctx->msg_trailer;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_header_size(struct Context *ctx) {
  return ctx->stream_sizes.cbHeader;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_trailer_size(struct Context *ctx) {
  return ctx->stream_sizes.cbTrailer;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_init_client(
  struct Context *ctx,
  int32_t verify
) {
  TLS_PARAMETERS tls_param;
  memset(&tls_param, 0, sizeof(TLS_PARAMETERS));
  tls_param.grbitDisabledProtocols = SP_PROT_TLS1_CLIENT;

  SCH_CREDENTIALS auth_data;
  memset(&auth_data, 0, sizeof(SCH_CREDENTIALS));
  auth_data.dwVersion = SCH_CREDENTIALS_VERSION;
  auth_data.dwFlags = SCH_CRED_IGNORE_NO_REVOCATION_CHECK;
  if (!verify)
    auth_data.dwFlags |= SCH_CRED_MANUAL_CRED_VALIDATION;
  auth_data.cTlsParameters = 1;
  auth_data.pTlsParameters = &tls_param;

  int32_t ret = AcquireCredentialsHandle(
    NULL, // `pszPrincipal`, usused by schannel
    UNISP_NAME, // `pszPackage`
    SECPKG_CRED_OUTBOUND, // `fCredentialUse`
    NULL, // `pvLogonID`, unused by schannel
    &auth_data, // `pAuthData`
    NULL, // `pGetKeyFn`, unused by schannel
    NULL, // `pGetKeyArgument`, unused by schannel
    &ctx->handle,
    NULL
  );
  if (ret == SEC_E_OK) {
    ctx->state = HandleInitialized;
    return 0;
  } else {
    return ret;
  }
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_add_root_certificate(
  struct Context *ctx,
  unsigned char *der
) {
  PCCERT_CONTEXT cert = CertCreateCertificateContext(
    X509_ASN_ENCODING | PKCS_7_ASN_ENCODING,
    der,
    Moonbit_array_length(der)
  );
  if (!cert)
    return GetLastError();

  HCERTSTORE store = get_or_create_custom_root_store(ctx);
  if (!store) {
    CertFreeCertificateContext(cert);
    return GetLastError();
  }

  if (ctx->custom_root_chain_engine) {
    CertFreeCertificateChainEngine(ctx->custom_root_chain_engine);
    ctx->custom_root_chain_engine = 0;
  }

  if (!CertAddCertificateContextToStore(
    store,
    cert,
    CERT_STORE_ADD_USE_EXISTING,
    NULL
  )) {
    int32_t err = GetLastError();
    CertFreeCertificateContext(cert);
    return err;
  }

  CertFreeCertificateContext(cert);
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_init_server(
  struct Context *ctx,
  unsigned char *pfx_content
) {
  const DWORD encoding_type = PKCS_7_ASN_ENCODING | X509_ASN_ENCODING;
  CRYPT_DATA_BLOB pfx_store = { Moonbit_array_length(pfx_content), pfx_content };
  HCERTSTORE cert_store = PFXImportCertStore(
    &pfx_store,
    NULL,
    0
  );
  if (!cert_store) {
    return GetLastError();
  }

  PCCERT_CONTEXT cert = CertFindCertificateInStore(
    cert_store,
    encoding_type,
    0,
    CERT_FIND_HAS_PRIVATE_KEY,
    NULL,
    NULL
  );

  if (!cert) {
    CertCloseStore(cert_store, 0);
    return GetLastError();
  }

  TLS_PARAMETERS tls_param;
  memset(&tls_param, 0, sizeof(TLS_PARAMETERS));
  tls_param.grbitDisabledProtocols = SP_PROT_TLS1_0_SERVER | SP_PROT_TLS1_1_SERVER;

  SCH_CREDENTIALS auth_data;
  memset(&auth_data, 0, sizeof(SCH_CREDENTIALS));
  auth_data.dwVersion = SCH_CREDENTIALS_VERSION;
  auth_data.dwCredFormat = SCH_CRED_FORMAT_CERT_HASH_STORE;
  auth_data.cCreds = 1;
  auth_data.paCred = &cert;
  auth_data.dwFlags = SCH_USE_STRONG_CRYPTO;
  auth_data.cTlsParameters = 1;
  auth_data.pTlsParameters = &tls_param;

  int32_t ret = AcquireCredentialsHandle(
    NULL, // `pszPrincipal`, usused by schannel
    UNISP_NAME, // `pszPackage`
    SECPKG_CRED_INBOUND, // `fCredentialUse`
    NULL, // `pvLogonID`, unused by schannel
    &auth_data, // `pAuthData`
    NULL, // `pGetKeyFn`, unused by schannel
    NULL, // `pGetKeyArgument`, unused by schannel
    &ctx->handle,
    NULL
  );

  CertFreeCertificateContext(cert);
  CertCloseStore(cert_store, 0);

  if (ret == SEC_E_OK) {
    ctx->state = HandleInitialized;
    return 0;
  } else {
    return ret;
  }
}

enum TlsState {
  Completed = 0,
  WantRead = 1,
  WantWrite = 2,
  Error = 3,
  Eof = 4,
  ReNegotiate = 5
};

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_connect(
  struct Context *ctx,
  LPWSTR host_name,
  char *in_buffer,
  int32_t in_buffer_offset,
  int32_t in_buffer_len,
  char *out_buffer,
  int32_t out_buffer_offset,
  int32_t out_buffer_len
) {
  SecBufferDesc input_desc, output_desc;
  SecBuffer input[2], output[1];

  if (ctx->state == ContextInitialized) {
    input[0].BufferType = SECBUFFER_TOKEN;
    input[0].cbBuffer = in_buffer_len;
    input[0].pvBuffer = in_buffer + in_buffer_offset;

    input[1].BufferType = SECBUFFER_EMPTY;
    input[1].cbBuffer = 0;
    input[1].pvBuffer = NULL;

    input_desc.ulVersion = SECBUFFER_VERSION;
    input_desc.cBuffers = 2;
    input_desc.pBuffers = input;
  }

  output[0].BufferType = SECBUFFER_TOKEN;
  output[0].cbBuffer = out_buffer_len;
  output[0].pvBuffer = out_buffer + out_buffer_offset;

  output_desc.ulVersion = SECBUFFER_VERSION;
  output_desc.cBuffers = 1;
  output_desc.pBuffers = output;

  ctx->bytes_read = ctx->bytes_to_write = 0;

  int32_t ret = InitializeSecurityContextW(
    &ctx->handle,
    ctx->state == ContextInitialized ? &ctx->context : NULL,
    host_name, // `pszTargetName`
    ISC_REQ_CONFIDENTIALITY | ISC_REQ_INTEGRITY, // `fContextReq`
    0, // `Reserved1`
    0, // `TargetDataRep`, unused by schannel
    ctx->state == ContextInitialized ? &input_desc : NULL, // `pInput`
    0, // `Reserved2`
    &ctx->context, // `phNewContext`
    &output_desc, // `pOutput`
    &ctx->context_attrs, // `pfContextAttr`
    NULL // `ptsExpiry`
  );

  ctx->bytes_read = in_buffer_len;
  if (input[1].BufferType == SECBUFFER_EXTRA)
    ctx->bytes_read -= input[1].cbBuffer;

  switch (ret) {
    case SEC_E_OK:
      ret = Completed;
      ctx->bytes_to_write = output[0].cbBuffer;
      QueryContextAttributes(&ctx->context, SECPKG_ATTR_STREAM_SIZES, &ctx->stream_sizes);
      break;
    case SEC_E_INCOMPLETE_MESSAGE:
      ctx->bytes_read = 0;
      ret = WantRead;
      break;
    case SEC_I_CONTINUE_NEEDED:
      ret = WantWrite;
      ctx->bytes_to_write = output[0].cbBuffer;
      break;
    case SEC_I_CONTEXT_EXPIRED:
      ret = Eof;
      ctx->bytes_to_write = output[0].cbBuffer;
      break;
    default:
      SetLastError(ret);
      return Error; // `HandshakeState::Error`
  }
  // non-error case, properly maintain `ctx->state`
  if (ctx->state == HandleInitialized)
    ctx->state = ContextInitialized;

  return ret;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_accept(
  struct Context *ctx,
  char *in_buffer,
  int32_t in_buffer_offset,
  int32_t in_buffer_len,
  char *out_buffer,
  int32_t out_buffer_offset,
  int32_t out_buffer_len
) {
  SecBufferDesc input_desc, output_desc;
  SecBuffer input[2], output[1];

  input[0].BufferType = SECBUFFER_TOKEN;
  input[0].cbBuffer = in_buffer_len;
  input[0].pvBuffer = in_buffer + in_buffer_offset;

  input[1].BufferType = SECBUFFER_EMPTY;
  input[1].cbBuffer = 0;
  input[1].pvBuffer = NULL;

  input_desc.ulVersion = SECBUFFER_VERSION;
  input_desc.cBuffers = 2;
  input_desc.pBuffers = input;

  output[0].BufferType = SECBUFFER_TOKEN;
  output[0].cbBuffer = out_buffer_len;
  output[0].pvBuffer = out_buffer + out_buffer_offset;

  output_desc.ulVersion = SECBUFFER_VERSION;
  output_desc.cBuffers = 1;
  output_desc.pBuffers = output;

  ctx->bytes_read = ctx->bytes_to_write = 0;

  int32_t ret = AcceptSecurityContext(
    &ctx->handle,
    ctx->state == ContextInitialized ? &ctx->context : NULL,
    &input_desc, // `pInput`
    ASC_REQ_CONFIDENTIALITY | ASC_REQ_INTEGRITY, // `fContextReq`
    0, // `TargetDataRep`, unused by schannel
    &ctx->context, // `phNewContext`
    &output_desc, // `pOutput`
    &ctx->context_attrs, // `pfContextAttr`
    NULL // `ptsExpiry`
  );

  ctx->bytes_read = in_buffer_len;
  if (input[1].BufferType == SECBUFFER_EXTRA)
    ctx->bytes_read -= input[1].cbBuffer;

  switch (ret) {
    case SEC_E_OK:
      ret = Completed;
      ctx->bytes_to_write = output[0].cbBuffer;
      QueryContextAttributes(&ctx->context, SECPKG_ATTR_STREAM_SIZES, &ctx->stream_sizes);
      break;
    case SEC_E_INCOMPLETE_MESSAGE:
      ctx->bytes_read = 0;
      ret = WantRead;
      break;
    case SEC_I_CONTINUE_NEEDED:
      ret = WantWrite;
      ctx->bytes_to_write = output[0].cbBuffer;
      break;
    case SEC_I_CONTEXT_EXPIRED:
      ret = Eof;
      break;
    default:
      SetLastError(ret);
      return Error;
  }
  // non-error case, properly maintain `ctx->state`
  if (
    ctx->state == HandleInitialized
    // Notice that if the first `ClientHello` has not been completely received,
    // `AcceptSecurityContext` will NOT initialize the `ctx->context` handle.
    // So it may take multiple `AcceptSecurityContext` before `ctx->handle` is properly initialized.
    && (ctx->context.dwLower != 0 || ctx->context.dwUpper != 0)
  ) {
    ctx->state = ContextInitialized;
  }

  return ret;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_read(
  struct Context *ctx,
  char *buffer,
  int32_t offset,
  int32_t len
) {
  SecBuffer buffers[4];
  buffers[0].BufferType = SECBUFFER_DATA;
  buffers[0].cbBuffer = len;
  buffers[0].pvBuffer = buffer + offset;
  for (int i = 1; i < 4; ++i) {
    buffers[i].BufferType = SECBUFFER_EMPTY;
    buffers[i].cbBuffer = 0;
    buffers[i].pvBuffer = NULL;
  }

  SecBufferDesc input_desc;
  input_desc.ulVersion = SECBUFFER_VERSION;
  input_desc.cBuffers = 4;
  input_desc.pBuffers = buffers;

  ctx->bytes_read = 0;

  int32_t ret = DecryptMessage(&ctx->context, &input_desc, 0, NULL);

  switch (ret) {
    case SEC_E_OK:
      ctx->msg_trailer = buffers[2].cbBuffer;
      ctx->bytes_read = len;
      if (buffers[3].BufferType = SECBUFFER_EXTRA) {
        ctx->bytes_read -= buffers[3].cbBuffer;
        ctx->msg_trailer -= buffers[3].cbBuffer;
      }
      return Completed;
    case SEC_E_INCOMPLETE_MESSAGE:
      return WantRead;
    case SEC_I_CONTEXT_EXPIRED:
      return Eof;
    case SEC_I_RENEGOTIATE:
      return ReNegotiate;
    default:
      SetLastError(ret);
      return Error;
  }
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_write(
  struct Context *ctx,
  char *buffer,
  int32_t offset,
  int32_t len
) {
  SecBuffer buffers[4];

  buffers[0].BufferType = SECBUFFER_STREAM_HEADER;
  buffers[0].cbBuffer = ctx->stream_sizes.cbHeader;
  buffers[0].pvBuffer = buffer + offset;

  buffers[1].BufferType = SECBUFFER_DATA;
  buffers[1].cbBuffer = len;
  buffers[1].pvBuffer = (char*)(buffers[0].pvBuffer) + buffers[0].cbBuffer;

  buffers[2].BufferType = SECBUFFER_STREAM_TRAILER;
  buffers[2].cbBuffer = ctx->stream_sizes.cbTrailer;
  buffers[2].pvBuffer = (char*)(buffers[1].pvBuffer) + buffers[1].cbBuffer;

  buffers[3].BufferType = SECBUFFER_EMPTY;
  buffers[3].cbBuffer = 0;
  buffers[3].pvBuffer = NULL;

  SecBufferDesc input_desc;
  input_desc.ulVersion = SECBUFFER_VERSION;
  input_desc.cBuffers = 4;
  input_desc.pBuffers = buffers;

  ctx->bytes_to_write = 0;

  int32_t ret = EncryptMessage(&ctx->context, 0, &input_desc, 0);

  switch (ret) {
    case SEC_E_OK:
      ctx->bytes_to_write =
        buffers[0].cbBuffer + buffers[1].cbBuffer + buffers[2].cbBuffer;
      return WantWrite;
    default:
      SetLastError(ret);
      return Error;
  }
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_shutdown(struct Context *ctx) {
  DWORD type = SCHANNEL_SHUTDOWN;

  SecBuffer buf;
  buf.BufferType = SECBUFFER_TOKEN;
  buf.cbBuffer = sizeof(DWORD);
  buf.pvBuffer = &type;

  SecBufferDesc buf_desc;
  buf_desc.ulVersion = SECBUFFER_VERSION;
  buf_desc.cBuffers = 1;
  buf_desc.pBuffers = &buf;

  return ApplyControlToken(&ctx->context, &buf_desc);
}

MOONBIT_FFI_EXPORT
CERT_CONTEXT *moonbitlang_async_schannel_get_peer_certificate(struct Context *ctx) {
  CERT_CONTEXT *cert = 0;
  int err = QueryContextAttributes(&ctx->context, SECPKG_ATTR_REMOTE_CERT_CONTEXT, &cert);
  if (err != SEC_E_OK && err != SEC_E_NO_CREDENTIALS) {
    SetLastError(err);
    return 0;
  } else {
    SetLastError(0);
  }

  return cert;
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_schannel_free_peer_certificate(CERT_CONTEXT *cert) {
  CertFreeCertificateContext(cert);
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_peer_certificate_length(CERT_CONTEXT *cert) {
  return cert->cbCertEncoded;
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_schannel_peer_certificate_blit_to(
  CERT_CONTEXT *cert,
  void *buf,
  int32_t len
) {
  memcpy(buf, cert->pbCertEncoded, len);
}

static
SEC_CHANNEL_BINDINGS *get_channel_binding(struct Context *ctx, int attribute) {
  SecPkgContext_Bindings bindings;
  int32_t err = QueryContextAttributes(&ctx->context, attribute, &bindings);
  if (err != SEC_E_OK) {
    SetLastError(err);
    return 0;
  }
  return bindings.Bindings;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_channel_binding_length(SEC_CHANNEL_BINDINGS *bindings) {
  return bindings->cbApplicationDataLength;
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_schannel_channel_binding_blit_to(
  SEC_CHANNEL_BINDINGS *bindings,
  void *buf,
  int32_t len
) {
  memcpy(buf, ((unsigned char *)bindings) + bindings->dwApplicationDataOffset, len);
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_schannel_free_channel_binding(SEC_CHANNEL_BINDINGS *bindings) {
  FreeContextBuffer(bindings);
}

MOONBIT_FFI_EXPORT
SEC_CHANNEL_BINDINGS *moonbitlang_async_schannel_unique_channel_binding(struct Context *ctx) {
  return get_channel_binding(ctx, SECPKG_ATTR_UNIQUE_BINDINGS);
}

MOONBIT_FFI_EXPORT
SEC_CHANNEL_BINDINGS *moonbitlang_async_schannel_server_endpoint_channel_binding(struct Context *ctx) {
  return get_channel_binding(ctx, SECPKG_ATTR_ENDPOINT_BINDINGS);
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_schannel_verify_peer_certificate(
  struct Context *ctx,
  LPWSTR host_name
) {
  PCCERT_CONTEXT cert = 0;
  PCCERT_CHAIN_CONTEXT chain = 0;
  HCERTCHAINENGINE chain_engine;
  CERT_CHAIN_PARA chain_para;
  CERT_CHAIN_POLICY_PARA policy_para;
  CERT_CHAIN_POLICY_STATUS policy_status;
  SSL_EXTRA_CERT_CHAIN_POLICY_PARA ssl_policy_para;

  int32_t err = QueryContextAttributes(
    &ctx->context,
    SECPKG_ATTR_REMOTE_CERT_CONTEXT,
    &cert
  );
  if (err != SEC_E_OK)
    return err;

  chain_engine = get_or_create_custom_root_chain_engine(ctx);
  if (!chain_engine) {
    CertFreeCertificateContext(cert);
    return GetLastError();
  }

  memset(&chain_para, 0, sizeof(CERT_CHAIN_PARA));
  chain_para.cbSize = sizeof(CERT_CHAIN_PARA);
  if (!CertGetCertificateChain(
    chain_engine,
    cert,
    NULL,
    NULL,
    &chain_para,
    0,
    NULL,
    &chain
  )) {
    err = GetLastError();
    CertFreeCertificateContext(cert);
    return err;
  }

  memset(&ssl_policy_para, 0, sizeof(SSL_EXTRA_CERT_CHAIN_POLICY_PARA));
  ssl_policy_para.cbSize = sizeof(SSL_EXTRA_CERT_CHAIN_POLICY_PARA);
  ssl_policy_para.dwAuthType = AUTHTYPE_SERVER;
  ssl_policy_para.fdwChecks = 0;
  ssl_policy_para.pwszServerName = host_name;

  memset(&policy_para, 0, sizeof(CERT_CHAIN_POLICY_PARA));
  policy_para.cbSize = sizeof(CERT_CHAIN_POLICY_PARA);
  policy_para.pvExtraPolicyPara = &ssl_policy_para;

  memset(&policy_status, 0, sizeof(CERT_CHAIN_POLICY_STATUS));
  policy_status.cbSize = sizeof(CERT_CHAIN_POLICY_STATUS);

  if (!CertVerifyCertificateChainPolicy(
    CERT_CHAIN_POLICY_SSL,
    chain,
    &policy_para,
    &policy_status
  )) {
    err = GetLastError();
    CertFreeCertificateChain(chain);
    CertFreeCertificateContext(cert);
    return err;
  }

  CertFreeCertificateChain(chain);
  CertFreeCertificateContext(cert);
  return policy_status.dwError;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tls_rand_bytes(void *buf, int32_t num) {
  return BCryptGenRandom(NULL, buf, num, BCRYPT_USE_SYSTEM_PREFERRED_RNG) == STATUS_SUCCESS;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tls_SHA1(void *data, int32_t num, void *out) {
  BCRYPT_ALG_HANDLE algorithm;
  BCRYPT_HASH_HANDLE hasher;
  NTSTATUS status;

  status = BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA1_ALGORITHM, NULL, 0);
  if (status != STATUS_SUCCESS)
    goto exit;

  status = BCryptCreateHash(algorithm, &hasher, NULL, 0, NULL, 0, 0);
  if (status != STATUS_SUCCESS)
    goto exit_with_algorithm;

  status = BCryptHashData(hasher, data, num, 0);
  if (status != STATUS_SUCCESS)
    goto exit_with_hasher;

  status = BCryptFinishHash(hasher, out, 20, 0);

exit_with_hasher:
  BCryptDestroyHash(hasher);

exit_with_algorithm:
  BCryptCloseAlgorithmProvider(algorithm, 0);

exit:
  if (status != STATUS_SUCCESS) {
    SetLastError(status);
    return 0;
  } else {
    return 1;
  }
}

#endif
