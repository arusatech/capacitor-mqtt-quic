#!/bin/bash
#
# Pinned repo URLs and versions for ngtcp2, nghttp3, and TLS (WolfSSL or QuicTLS).
# Sourced by ios/*.sh and android/*.sh build scripts for reproducible builds
# and compatibility with MQTT-over-QUIC server (mqttd).
# Values should match ref-code/VERSION.txt.
# Default TLS backend: WolfSSL (TLS 1.3 + QUIC). Set USE_WOLFSSL=0 to use QuicTLS.
# All builds use WolfSSL by default; single source of truth for default TLS backend.
export USE_WOLFSSL="${USE_WOLFSSL:-1}"

# QUIC is enabled by default for WolfSSL and ngtcp2; set ENABLE_QUIC=0 to disable.
export ENABLE_QUIC="${ENABLE_QUIC:-1}"
export NGHTTP3_REPO_URL="${NGHTTP3_REPO_URL:-https://github.com/ngtcp2/nghttp3.git}"
export NGHTTP3_COMMIT="${NGHTTP3_COMMIT:-78f27c1}"

export NGTCP2_REPO_URL="${NGTCP2_REPO_URL:-https://github.com/ngtcp2/ngtcp2.git}"
export NGTCP2_COMMIT="${NGTCP2_COMMIT:-3ce3bbead}"

# WolfSSL: TLS 1.3 + QUIC (configurable). Used by default for ngtcp2/nghttp3.
export WOLFSSL_REPO_URL="${WOLFSSL_REPO_URL:-https://github.com/wolfSSL/wolfssl.git}"
export WOLFSSL_TAG="${WOLFSSL_TAG:-v5.8.4-stable}"

# QuicTLS (optional; when USE_WOLFSSL=0)
export QUICTLS_REPO_URL="${QUICTLS_REPO_URL:-https://github.com/quictls/quictls.git}"
export OPENSSL_COMMIT="${OPENSSL_COMMIT:-2cc13b7c86fd76e5b45b5faa4ca365a602f92392}"
