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

#include <sys/socket.h>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netinet/udp.h>
#include <netinet/tcp.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <moonbit.h>

typedef struct moonbit_getaddrinfo_s
{
    struct addrinfo *addr;
} moonbit_getaddrinfo_t;

static inline void empty_function(void *self)
{
    // no-op: empty function
}

static inline void
moonbit_getaddrinfo_finalize(void *object)
{
    moonbit_getaddrinfo_t *addr_info = object;
    if (addr_info && addr_info->addr)
    {
        freeaddrinfo(addr_info->addr);
        addr_info->addr = NULL;
    }
}

MOONBIT_FFI_EXPORT
int32_t
moonbitlang_is_null_pointer(void *ptr)
{
    return ptr == NULL;
}

MOONBIT_FFI_EXPORT
moonbit_getaddrinfo_t *
moonbitlang_getaddrinfo_make_ffi(
    moonbit_bytes_t hostname,
    moonbit_bytes_t service,
    int ai_flags,
    int ai_family,
    int ai_socktype,
    int ai_protocol)
{
    struct addrinfo hints, *result;
    memset(&hints, 0, sizeof(hints));
    hints.ai_flags = ai_flags;
    // hints.ai_family = ai_family;
    hints.ai_family = AF_UNSPEC;   // IPv4 or IPv6
    hints.ai_socktype = ai_socktype;
    hints.ai_protocol = ai_protocol;
    int status = getaddrinfo(
        (const char *)hostname,
        (const char *)service,
        // NULL,
        &hints,
        &result);
    if (status != 0)
    {
        return NULL; // Error handling
    }

    moonbit_getaddrinfo_t *addr =
        (moonbit_getaddrinfo_t *)moonbit_make_external_object(
            moonbit_getaddrinfo_finalize, sizeof(moonbit_getaddrinfo_t));
    memset(addr, 0, sizeof(moonbit_getaddrinfo_t));
    addr->addr = result;
    return addr;
}

typedef struct moonbit_addrinfo_results_iterate_cb_s
{
    int32_t (*code)(
        struct moonbit_addrinfo_results_iterate_cb_s *,
        int32_t ai_flags,
        int32_t ai_family,
        int32_t ai_socktype,
        int32_t ai_protocol,
        moonbit_bytes_t ai_addr);
} moonbit_addrinfo_results_iterate_cb_t;

MOONBIT_FFI_EXPORT
int32_t
moonbitlang_addrinfo_results_iterate_ffi(
    moonbit_getaddrinfo_t *addrinfo,
    moonbit_addrinfo_results_iterate_cb_t *cb)
{
    int32_t terminated = 0;
    for (struct addrinfo *ai = addrinfo->addr; ai != NULL; ai = ai->ai_next)
    {
        moonbit_bytes_t sockaddr = moonbit_make_bytes(ai->ai_addrlen, 0);
        memcpy((void *)sockaddr, ai->ai_addr, ai->ai_addrlen);
        moonbit_incref(cb);
        terminated = cb->code(
            cb, ai->ai_flags, ai->ai_family, ai->ai_socktype, ai->ai_protocol,
            sockaddr);
        if (terminated)
        {
            break;
        }
    }
    return terminated;
}

MOONBIT_FFI_EXPORT
int32_t
moonbitlang_ipv4_addrlen_ffi(void)
{
    return INET_ADDRSTRLEN;
}

MOONBIT_FFI_EXPORT
int32_t
moonbitlang_ipv6_addrlen_ffi(void)
{
    return INET6_ADDRSTRLEN;
}

typedef struct moonbit_get_ip_name_port_cb_s
{
    int32_t (*code)(
        struct moonbit_get_ip_name_port_cb_s *,
        int32_t ai_family,
        int32_t port,
        int32_t flowinfo,
        int32_t scope_id);
} moonbit_get_ip_name_port_cb_t;
MOONBIT_FFI_EXPORT
int32_t
moonbitlang_get_ip_name_ffi(
    const struct sockaddr *src,
    moonbit_get_ip_name_port_cb_t *cb)
{
    if (src == NULL || cb == NULL)
    {
        return -1;
    }

    char ip_str[INET6_ADDRSTRLEN];
    int flowinfo = 0;
    int scope_id = 0;
    int port = 0;
    if (src->sa_family == AF_INET)
    {
        const struct sockaddr_in *sa4 = (const struct sockaddr_in *)src;
        if (inet_ntop(AF_INET, &sa4->sin_addr, ip_str, sizeof(ip_str)) == NULL)
        {
            return -1;
        }
        port = ntohs(sa4->sin_port);
    }
    else if (src->sa_family == AF_INET6)
    {
        const struct sockaddr_in6 *sa6 = (const struct sockaddr_in6 *)src;
        if (inet_ntop(AF_INET6, &sa6->sin6_addr, ip_str, sizeof(ip_str)) == NULL)
        {
            return -1;
        }
        flowinfo = sa6->sin6_flowinfo;
        scope_id = sa6->sin6_scope_id;
        port = ntohs(sa6->sin6_port);
    }
    else
    {
        return -1;
    }
    moonbit_incref(cb);
    cb->code(
        cb, src->sa_family, port, flowinfo, scope_id);
    return 0;
}

MOONBIT_FFI_EXPORT
int32_t
moonbitlang_get_ipv4_name_ffi(const struct sockaddr_in *src, moonbit_bytes_t dst)
{
    if (src == NULL || dst == NULL)
    {
        return -1;
    }
    char ip_str[INET_ADDRSTRLEN];
    if (inet_ntop(AF_INET, &src->sin_addr, ip_str, sizeof(ip_str)) == NULL)
    {
        return -1;
    }
    int len = strlen(ip_str);
    memcpy(dst, ip_str, len);
    dst[len] = '\0';
    return len;
}

MOONBIT_FFI_EXPORT
int32_t
moonbitlang_get_ipv6_name_ffi(const struct sockaddr_in6 *src, moonbit_bytes_t dst)
{
    if (src == NULL || dst == NULL)
    {
        return -1;
    }
    char ip_str[INET6_ADDRSTRLEN];
    if (inet_ntop(AF_INET6, &src->sin6_addr, ip_str, sizeof(ip_str)) == NULL)
    {
        return -1;
    }
    int len = strlen(ip_str);
    memcpy(dst, ip_str, len);
    dst[len] = '\0';
    return len;
}

MOONBIT_FFI_EXPORT struct sockaddr_storage *moonbitlang_create_sockaddr_storage_ffi()
{
    struct sockaddr_storage *addr =
        moonbit_make_external_object(empty_function, sizeof(struct sockaddr_storage));
    memset(addr, 0, sizeof(struct sockaddr_storage));
    addr->ss_family = AF_INET; // Default to IPv4
    return addr;
}

// Constants for socket domains
MOONBIT_FFI_EXPORT int32_t moonbitlang_AF_INET_ffi(void) { return AF_INET; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_AF_INET6_ffi(void) { return AF_INET6; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_AF_UNIX_ffi(void) { return AF_UNIX; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_AF_UNSPEC_ffi(void) { return AF_UNSPEC; }

// Constants for socket types
MOONBIT_FFI_EXPORT int32_t moonbitlang_SOCK_STREAM_ffi(void) { return SOCK_STREAM; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_SOCK_DGRAM_ffi(void) { return SOCK_DGRAM; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_SOCK_RAW_ffi(void) { return SOCK_RAW; }

// Constants for socket protocols
MOONBIT_FFI_EXPORT int32_t moonbitlang_IPPROTO_TCP_ffi(void) { return IPPROTO_TCP; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_IPPROTO_UDP_ffi(void) { return IPPROTO_UDP; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_IPPROTO_ICMP_ffi(void) { return IPPROTO_ICMP; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_IPPROTO_ICMPV6_ffi(void) { return IPPROTO_ICMPV6; }

// Constants for socket options
MOONBIT_FFI_EXPORT int32_t moonbitlang_SOL_SOCKET_ffi(void) { return SOL_SOCKET; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_SO_REUSEADDR_ffi(void) { return SO_REUSEADDR; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_SO_KEEPALIVE_ffi(void) { return SO_KEEPALIVE; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_SO_RCVBUF_ffi(void) { return SO_RCVBUF; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_SO_SNDBUF_ffi(void) { return SO_SNDBUF; }

// Constants for socket shutdown modes
MOONBIT_FFI_EXPORT int32_t moonbitlang_SHUT_RD_ffi(void) { return SHUT_RD; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_SHUT_WR_ffi(void) { return SHUT_WR; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_SHUT_RDWR_ffi(void) { return SHUT_RDWR; }

// Constants for getaddrinfo flags
MOONBIT_FFI_EXPORT int32_t moonbitlang_FLAG_AI_PASSIVE_ffi(void) { return AI_PASSIVE; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_FLAG_AI_CANONNAME_ffi(void) { return AI_CANONNAME; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_FLAG_AI_ALL_ffi(void) { return AI_ALL; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_FLAG_AI_NUMERICHOST_ffi(void) { return AI_NUMERICHOST; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_FLAG_AI_NUMERICSERV_ffi(void) { return AI_NUMERICSERV; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_FLAG_AI_ADDRCONFIG_ffi(void) { return AI_ADDRCONFIG; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_FLAG_AI_V4MAPPED_ffi(void) { return AI_V4MAPPED; }

/// Constants for setsockopt
