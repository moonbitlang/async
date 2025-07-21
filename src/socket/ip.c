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

#include <arpa/inet.h>
#include <string.h>
#include <netdb.h>
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <sys/socket.h>
#include <netinet/in.h>
#endif
#include <moonbit.h>

static inline void empty_function(void *self)
{
    // no-op: empty function
}

MOONBIT_FFI_EXPORT
int32_t
moonbitlang_ipv4_addrlen(void)
{
    return INET_ADDRSTRLEN;
}

MOONBIT_FFI_EXPORT
int32_t
moonbitlang_ipv6_addrlen(void)
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
moonbitlang_get_ip_addr_detail(
    const struct sockaddr *src,
    moonbit_get_ip_name_port_cb_t *cb)
{
    if (src == NULL || cb == NULL)
    {
        return -1;
    }

    // Now ip_str not passed as a parameter
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
moonbitlang_get_ipv4_name(const struct sockaddr_in *src, moonbit_bytes_t dst)
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
moonbitlang_get_ipv6_name(const struct sockaddr_in6 *src, moonbit_bytes_t dst)
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

MOONBIT_FFI_EXPORT struct sockaddr_storage *moonbitlang_create_sockaddr_storage()
{
    struct sockaddr_storage *addr =
        moonbit_make_external_object(empty_function, sizeof(struct sockaddr_storage));
    memset(addr, 0, sizeof(struct sockaddr_storage));
    addr->ss_family = AF_INET; // Default to IPv4
    return addr;
}


// Constants for socket domains
MOONBIT_FFI_EXPORT int32_t moonbitlang_AF_INET(void) { return AF_INET; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_AF_INET6(void) { return AF_INET6; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_AF_UNIX(void) {
#if defined(_WIN32)
    #include <ws2def.h>
    #ifndef AF_UNIX
        #define AF_UNIX AF_LOCAL
    #endif
    return AF_UNIX;
#else
    return AF_UNIX;
#endif
}
MOONBIT_FFI_EXPORT int32_t moonbitlang_AF_UNSPEC(void) { return AF_UNSPEC; }


// Constants for socket types
MOONBIT_FFI_EXPORT int32_t moonbitlang_SOCK_STREAM(void) { return SOCK_STREAM; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_SOCK_DGRAM(void) { return SOCK_DGRAM; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_SOCK_RAW(void) { return SOCK_RAW; }

// Constants for socket protocols
MOONBIT_FFI_EXPORT int32_t moonbitlang_IPPROTO_IP(void) { return IPPROTO_IP; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_IPPROTO_TCP(void) { return IPPROTO_TCP; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_IPPROTO_UDP(void) { return IPPROTO_UDP; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_IPPROTO_ICMP(void) { return IPPROTO_ICMP; }
MOONBIT_FFI_EXPORT int32_t moonbitlang_IPPROTO_ICMPV6(void) { return IPPROTO_ICMPV6; }