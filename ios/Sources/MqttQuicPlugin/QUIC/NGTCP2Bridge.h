#pragma once

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *NGTCP2ClientHandle;

NGTCP2ClientHandle ngtcp2_client_create(void);
void ngtcp2_client_destroy(NGTCP2ClientHandle handle);

int ngtcp2_client_connect(NGTCP2ClientHandle handle, const char *host, uint16_t port, const char *alpn);
int64_t ngtcp2_client_open_stream(NGTCP2ClientHandle handle);
int ngtcp2_client_write_stream(NGTCP2ClientHandle handle, int64_t stream_id,
                               const uint8_t *data, size_t datalen, int fin);
ssize_t ngtcp2_client_read_stream(NGTCP2ClientHandle handle, int64_t stream_id,
                                  uint8_t *buffer, size_t maxlen);
int ngtcp2_client_close_stream(NGTCP2ClientHandle handle, int64_t stream_id);
int ngtcp2_client_close(NGTCP2ClientHandle handle);
int ngtcp2_client_is_connected(NGTCP2ClientHandle handle);
const char *ngtcp2_client_last_error(NGTCP2ClientHandle handle);

/** UDP reachability check to host:port (e.g. MQTT/QUIC server). Returns 0 on success, -1 on failure. */
int ngtcp2_ping_server(const char *host, uint16_t port);

#ifdef __cplusplus
}
#endif
