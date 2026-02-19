//
// ngtcp2_jni.cpp
// MqttQuicPlugin
//
// JNI wrapper for ngtcp2 QUIC client implementation.
//

#include <jni.h>
#include <android/log.h>

#include <ngtcp2/ngtcp2.h>
#include <ngtcp2/ngtcp2_crypto.h>
#include <ngtcp2/ngtcp2_crypto_wolfssl.h>

#include <wolfssl/ssl.h>

#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cinttypes>
#include <cstdarg>
#include <cstdlib>
#include <cstdio>
#include <condition_variable>
#include <deque>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#define LOG_TAG "NGTCP2JNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

static uint64_t now_ts() {
  struct timespec tp;
  if (clock_gettime(CLOCK_MONOTONIC, &tp) != 0) {
    return 0;
  }
  return (uint64_t)tp.tv_sec * NGTCP2_SECONDS + (uint64_t)tp.tv_nsec;
}

static void log_printf(void *user_data, const char *fmt, ...) {
  (void)user_data;
  va_list ap;
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  fprintf(stderr, "\n");
}

struct StreamState {
  std::deque<uint8_t> recv_buf;
  bool fin_received = false;
  bool closed = false;
};

struct OutgoingChunk {
  std::vector<uint8_t> data;
  size_t offset = 0;
  bool fin = false;
};

class QuicClient {
 public:
  QuicClient(std::string host, uint16_t port)
      : QuicClient(std::move(host), "", port) {}

  QuicClient(std::string host_for_tls, std::string connect_addr, uint16_t port)
      : host_(std::move(host_for_tls)),
        connect_addr_(connect_addr.empty() ? host_ : std::move(connect_addr)),
        port_(port),
        fd_(-1),
        ssl_ctx_(nullptr),
        ssl_(nullptr),
        conn_(nullptr),
        running_(false),
        connected_(false),
        close_requested_(false) {
    ngtcp2_ccerr_default(&last_error_);
    conn_ref_.get_conn = get_conn;
    conn_ref_.user_data = this;
    wakeup_fds_[0] = -1;
    wakeup_fds_[1] = -1;
  }

  ~QuicClient() { close(); }

  int connect(const std::string &alpn) {
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      if (connected_) {
        return 0;
      }
    }
    clearError();
    if (init_socket() != 0) {
      return -1;
    }
    if (init_tls(alpn) != 0) {
      return -1;
    }
    if (init_quic() != 0) {
      return -1;
    }
    if (init_wakeup_pipe() != 0) {
      return -1;
    }

    running_ = true;
    worker_ = std::thread([this]() { run_loop(); });
    signal_wakeup();

    std::unique_lock<std::mutex> wait_lock(state_mutex_);
    if (!cv_state_.wait_for(wait_lock, std::chrono::seconds(15), [this]() {
          return connected_ || !running_;
        })) {
      setError("QUIC handshake timed out");
      return -1;
    }
    if (!connected_) {
      if (last_error_str_.empty()) {
        setError("QUIC handshake failed");
      }
      return -1;
    }
    return 0;
  }

  int64_t open_stream() {
    if (!conn_) {
      setError("QUIC connection not initialized");
      return -1;
    }
    int64_t stream_id = -1;
    int rv = ngtcp2_conn_open_bidi_stream(conn_, &stream_id, nullptr);
    if (rv != 0) {
      setError(ngtcp2_strerror(rv));
      return -1;
    }
    {
      std::lock_guard<std::mutex> lock(stream_mutex_);
      streams_.emplace(stream_id, StreamState{});
    }
    signal_wakeup();
    return stream_id;
  }

  int write_stream(int64_t stream_id, const uint8_t *data, size_t datalen,
                   bool fin) {
    if (!conn_) {
      setError("QUIC connection not initialized");
      return -1;
    }
    OutgoingChunk chunk;
    chunk.data.assign(data, data + datalen);
    chunk.offset = 0;
    chunk.fin = fin;
    {
      std::lock_guard<std::mutex> lock(out_mutex_);
      outgoing_[stream_id].push_back(std::move(chunk));
    }
    signal_wakeup();
    return 0;
  }

  ssize_t read_stream(int64_t stream_id, uint8_t *buffer, size_t maxlen) {
    std::lock_guard<std::mutex> lock(stream_mutex_);
    auto it = streams_.find(stream_id);
    if (it == streams_.end()) {
      return 0;
    }
    StreamState &state = it->second;
    size_t n = std::min(maxlen, state.recv_buf.size());
    for (size_t i = 0; i < n; ++i) {
      buffer[i] = state.recv_buf.front();
      state.recv_buf.pop_front();
    }
    if (n > 0) {
      LOGI("read_stream stream_id=%" PRId64 " returning %zu bytes", (int64_t)stream_id, n);
    }
    return (ssize_t)n;
  }

  int close_stream(int64_t stream_id) {
    if (!conn_) {
      return 0;
    }
    int rv = ngtcp2_conn_shutdown_stream_write(conn_, 0, stream_id, 0);
    if (rv != 0) {
      setError(ngtcp2_strerror(rv));
      return -1;
    }
    signal_wakeup();
    return 0;
  }

  int close() {
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      if (!running_) {
        cleanup();
        return 0;
      }
      close_requested_ = true;
    }
    signal_wakeup();
    if (worker_.joinable()) {
      worker_.join();
    }
    cleanup();
    return 0;
  }

  int is_connected() const { return connected_ ? 1 : 0; }

  const char *last_error() const { return last_error_str_.c_str(); }

  int on_recv_stream_data(uint32_t flags, int64_t stream_id,
                          const uint8_t *data, size_t datalen) {
    std::lock_guard<std::mutex> lock(stream_mutex_);
    StreamState &state = streams_[stream_id];
    state.recv_buf.insert(state.recv_buf.end(), data, data + datalen);
    LOGI("recv stream data stream_id=%" PRId64 " len=%zu recv_buf_total=%zu",
         (int64_t)stream_id, datalen, state.recv_buf.size());
    if (flags & NGTCP2_STREAM_DATA_FLAG_FIN) {
      state.fin_received = true;
    }
    return 0;
  }

  int on_handshake_completed() {
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      connected_ = true;
    }
    LOGI("ngtcp2 handshake completed");
    cv_state_.notify_all();
    return 0;
  }

 private:
  static ngtcp2_conn *get_conn(ngtcp2_crypto_conn_ref *conn_ref) {
    auto *client = static_cast<QuicClient *>(conn_ref->user_data);
    return client->conn_;
  }

  int init_socket() {
    struct addrinfo hints;
    struct addrinfo *res = nullptr;
    memset(&hints, 0, sizeof(hints));
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_family = AF_UNSPEC;

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%u", port_);
    const char *resolve_host = connect_addr_.empty() ? host_.c_str() : connect_addr_.c_str();
    int rv = getaddrinfo(resolve_host, port_str, &hints, &res);
    if (rv != 0) {
      setError(gai_strerror(rv));
      return -1;
    }

    int fd = -1;
    for (auto *rp = res; rp; rp = rp->ai_next) {
      fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
      if (fd == -1) {
        continue;
      }
      if (::connect(fd, rp->ai_addr, rp->ai_addrlen) == 0) {
        memcpy(&remote_addr_, rp->ai_addr, rp->ai_addrlen);
        remote_addrlen_ = (socklen_t)rp->ai_addrlen;
        char buf[INET6_ADDRSTRLEN];
        const void *src = (rp->ai_family == AF_INET)
            ? (void *)&((struct sockaddr_in *)rp->ai_addr)->sin_addr
            : (void *)&((struct sockaddr_in6 *)rp->ai_addr)->sin6_addr;
        if (inet_ntop(rp->ai_family, src, buf, sizeof(buf))) {
          resolved_address_ = buf;
        }
        break;
      }
      ::close(fd);
      fd = -1;
    }
    freeaddrinfo(res);
    if (fd == -1) {
      setError("Failed to create/connect UDP socket");
      return -1;
    }

    local_addrlen_ = sizeof(local_addr_);
    if (getsockname(fd, (struct sockaddr *)&local_addr_, &local_addrlen_) !=
        0) {
      setError("getsockname failed");
      ::close(fd);
      return -1;
    }

    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0) {
      fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }

    fd_ = fd;
    return 0;
  }

  int init_tls(const std::string &alpn) {
    ssl_ctx_ = wolfSSL_CTX_new(wolfTLS_client_method());
    if (!ssl_ctx_) {
      setError("wolfSSL_CTX_new failed");
      return -1;
    }
    if (ngtcp2_crypto_wolfssl_configure_client_context(ssl_ctx_) != 0) {
      setError("ngtcp2_crypto_wolfssl_configure_client_context failed");
      return -1;
    }
    wolfSSL_CTX_set_verify(ssl_ctx_, WOLFSSL_VERIFY_PEER, nullptr);

    ssl_ = wolfSSL_new(ssl_ctx_);
    if (!ssl_) {
      setError("wolfSSL_new failed");
      return -1;
    }
    wolfSSL_set_app_data(ssl_, &conn_ref_);
    wolfSSL_set_connect_state(ssl_);

    std::string alpn_vec;
    alpn_vec.push_back(static_cast<char>(alpn.size()));
    alpn_vec.append(alpn);
    wolfSSL_set_alpn_protos(ssl_,
                            reinterpret_cast<const unsigned char *>(alpn_vec.data()),
                            (unsigned int)alpn_vec.size());
    wolfSSL_set_tlsext_host_name(ssl_, host_.c_str());

    if (wolfSSL_set1_host(ssl_, host_.c_str()) != 1) {
      setError("wolfSSL_set1_host failed");
      return -1;
    }

    bool ca_loaded = false;
    const char *ca_file = std::getenv("MQTT_QUIC_CA_FILE");
    const char *ca_path = std::getenv("MQTT_QUIC_CA_PATH");
    const char *file_arg = (ca_file && ca_file[0] != '\0') ? ca_file : nullptr;
    const char *path_arg = (ca_path && ca_path[0] != '\0') ? ca_path : nullptr;
    if (file_arg || path_arg) {
      if (wolfSSL_CTX_load_verify_locations(ssl_ctx_, file_arg, path_arg) == 1) {
        ca_loaded = true;
      } else {
        setError("Failed to load CA bundle from MQTT_QUIC_CA_FILE/CA_PATH");
        return -1;
      }
    }
    if (!ca_loaded && wolfSSL_CTX_set_default_verify_paths(ssl_ctx_) == 1) {
      ca_loaded = true;
    }
    if (!ca_loaded && wolfSSL_CTX_load_system_CA_certs(ssl_ctx_) == 1) {
      ca_loaded = true;
    }
    if (!ca_loaded) {
      setError("No CA bundle available for TLS verification");
      return -1;
    }

    return 0;
  }

  int init_quic() {
    ngtcp2_callbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.client_initial = ngtcp2_crypto_client_initial_cb;
    callbacks.recv_crypto_data = ngtcp2_crypto_recv_crypto_data_cb;
    callbacks.encrypt = ngtcp2_crypto_encrypt_cb;
    callbacks.decrypt = ngtcp2_crypto_decrypt_cb;
    callbacks.hp_mask = ngtcp2_crypto_hp_mask_cb;
    callbacks.recv_retry = ngtcp2_crypto_recv_retry_cb;
    callbacks.update_key = ngtcp2_crypto_update_key_cb;
    callbacks.delete_crypto_aead_ctx = ngtcp2_crypto_delete_crypto_aead_ctx_cb;
    callbacks.delete_crypto_cipher_ctx = ngtcp2_crypto_delete_crypto_cipher_ctx_cb;
    callbacks.get_path_challenge_data = ngtcp2_crypto_get_path_challenge_data_cb;
    callbacks.version_negotiation = ngtcp2_crypto_version_negotiation_cb;
    callbacks.handshake_completed = handshake_completed_cb;
    callbacks.handshake_confirmed = handshake_completed_cb;
    callbacks.recv_stream_data = recv_stream_data_cb;
    callbacks.acked_stream_data_offset = acked_stream_data_offset_cb;
    callbacks.stream_close = stream_close_cb;
    callbacks.extend_max_local_streams_bidi = extend_max_local_streams_bidi_cb;
    callbacks.rand = rand_cb;
    callbacks.get_new_connection_id = get_new_connection_id_cb;

    ngtcp2_settings settings;
    ngtcp2_transport_params params;
    ngtcp2_settings_default(&settings);
    settings.initial_ts = now_ts();
    settings.log_printf = log_printf;
    settings.handshake_timeout = 10 * NGTCP2_SECONDS;

    ngtcp2_transport_params_default(&params);
    /* Set all transport params explicitly so server validation passes (active_connection_id_limit>=2, max_ack_delay in range). Use non-default values so they are encoded on the wire. */
    params.initial_max_streams_bidi = 8;
    params.initial_max_streams_uni = 8;
    params.initial_max_stream_data_bidi_local = 256 * 1024;
    params.initial_max_stream_data_bidi_remote = 256 * 1024;
    params.initial_max_stream_data_uni = 256 * 1024;
    params.initial_max_data = 1024 * 1024;
    params.active_connection_id_limit = 8;
    params.max_ack_delay = 1 * NGTCP2_MILLISECONDS;
    params.max_idle_timeout = 30 * NGTCP2_SECONDS;

    ngtcp2_cid dcid, scid;
    dcid.datalen = NGTCP2_MIN_INITIAL_DCIDLEN;
    if (wolfSSL_RAND_bytes(dcid.data, (int)dcid.datalen) != 1) {
      setError("wolfSSL_RAND_bytes failed");
      return -1;
    }
    scid.datalen = 8;
    if (wolfSSL_RAND_bytes(scid.data, (int)scid.datalen) != 1) {
      setError("wolfSSL_RAND_bytes failed");
      return -1;
    }

    ngtcp2_path path = {
      .local = {.addr = (struct sockaddr *)&local_addr_,
                .addrlen = local_addrlen_},
      .remote = {.addr = (struct sockaddr *)&remote_addr_,
                 .addrlen = remote_addrlen_},
    };

    int rv = ngtcp2_conn_client_new(&conn_, &dcid, &scid, &path,
                                    NGTCP2_PROTO_VER_V1, &callbacks, &settings,
                                    &params, nullptr, this);
    if (rv != 0) {
      setError(ngtcp2_strerror(rv));
      return -1;
    }
    ngtcp2_conn_set_tls_native_handle(conn_, ssl_);
    return 0;
  }

  int init_wakeup_pipe() {
    if (pipe(wakeup_fds_) != 0) {
      setError("Failed to create wakeup pipe");
      return -1;
    }
    int flags = fcntl(wakeup_fds_[0], F_GETFL, 0);
    if (flags >= 0) {
      fcntl(wakeup_fds_[0], F_SETFL, flags | O_NONBLOCK);
    }
    flags = fcntl(wakeup_fds_[1], F_GETFL, 0);
    if (flags >= 0) {
      fcntl(wakeup_fds_[1], F_SETFL, flags | O_NONBLOCK);
    }
    return 0;
  }

  void run_loop() {
    send_pending_packets();
    while (running_) {
      int timeout_ms = compute_timeout_ms();
      struct pollfd fds[2];
      fds[0].fd = fd_;
      fds[0].events = POLLIN;
      fds[1].fd = wakeup_fds_[0];
      fds[1].events = POLLIN;

      int rv = poll(fds, 2, timeout_ms);
      if (rv > 0) {
        if (fds[1].revents & POLLIN) {
          drain_wakeup();
        }
        if (fds[0].revents & POLLIN) {
          if (read_packets() != 0) {
            break;
          }
        }
      }

      if (handle_expiry() != 0) {
        break;
      }
      if (send_pending_packets() != 0) {
        break;
      }

      if (close_requested_) {
        send_connection_close();
        break;
      }
    }

    running_ = false;
    cv_state_.notify_all();
  }

  int compute_timeout_ms() {
    if (!conn_) {
      return 100;
    }
    uint64_t expiry = ngtcp2_conn_get_expiry(conn_);
    uint64_t now = now_ts();
    if (expiry <= now) {
      return 0;
    }
    uint64_t delta_ms = (expiry - now) / (NGTCP2_MILLISECONDS);
    if (delta_ms > 1000) {
      return 1000;
    }
    return (int)delta_ms;
  }

  int read_packets() {
    uint8_t buf[65536];
    for (;;) {
      ssize_t nread = recv(fd_, buf, sizeof(buf), 0);
      if (nread <= 0) {
        break;
      }
      ngtcp2_path path = {
        .local = {.addr = (struct sockaddr *)&local_addr_,
                  .addrlen = local_addrlen_},
        .remote = {.addr = (struct sockaddr *)&remote_addr_,
                   .addrlen = remote_addrlen_},
      };
      ngtcp2_pkt_info pi;
      memset(&pi, 0, sizeof(pi));
      int rv = ngtcp2_conn_read_pkt(conn_, &path, &pi, buf, (size_t)nread,
                                    now_ts());
      if (rv != 0) {
        setError(ngtcp2_strerror(rv));
        return -1;
      }
    }
    return 0;
  }

  int handle_expiry() {
    if (!conn_) {
      return 0;
    }
    uint64_t now = now_ts();
    uint64_t expiry = ngtcp2_conn_get_expiry(conn_);
    if (expiry > now) {
      return 0;
    }
    int rv = ngtcp2_conn_handle_expiry(conn_, now);
    if (rv != 0) {
      setError(ngtcp2_strerror(rv));
      return -1;
    }
    return 0;
  }

  int send_pending_packets() {
    if (!conn_) {
      return 0;
    }
    for (;;) {
      int64_t stream_id = -1;
      uint32_t flags = NGTCP2_WRITE_STREAM_FLAG_MORE;
      ngtcp2_vec datav;
      size_t datavcnt = 0;
      bool fin = false;
      {
        std::lock_guard<std::mutex> lock(out_mutex_);
        auto it = outgoing_.begin();
        if (it != outgoing_.end() && !it->second.empty()) {
          stream_id = it->first;
          OutgoingChunk &chunk = it->second.front();
          datav.base = chunk.data.data() + chunk.offset;
          datav.len = chunk.data.size() - chunk.offset;
          datavcnt = 1;
          fin = chunk.fin;
        }
      }

      if (fin) {
        flags |= NGTCP2_WRITE_STREAM_FLAG_FIN;
      }

      ngtcp2_path_storage ps;
      ngtcp2_path_storage_zero(&ps);
      ngtcp2_pkt_info pi;
      ngtcp2_ssize nwrite = 0;
      ngtcp2_ssize wdatalen = 0;
      uint8_t buf[1452];
      nwrite = ngtcp2_conn_writev_stream(conn_, &ps.path, &pi, buf, sizeof(buf),
                                         &wdatalen, flags, stream_id,
                                         datavcnt ? &datav : nullptr, datavcnt,
                                         now_ts());
      if (nwrite < 0) {
        if (nwrite == NGTCP2_ERR_WRITE_MORE) {
          std::lock_guard<std::mutex> lock(out_mutex_);
          auto it = outgoing_.find(stream_id);
          if (it != outgoing_.end() && !it->second.empty()) {
            it->second.front().offset += (size_t)wdatalen;
            if (it->second.front().offset >= it->second.front().data.size()) {
              it->second.pop_front();
            }
          }
          continue;
        }
        setError(ngtcp2_strerror((int)nwrite));
        return -1;
      }
      if (nwrite == 0) {
        return 0;
      }

      if (wdatalen > 0) {
        std::lock_guard<std::mutex> lock(out_mutex_);
        auto it = outgoing_.find(stream_id);
        if (it != outgoing_.end() && !it->second.empty()) {
          it->second.front().offset += (size_t)wdatalen;
          if (it->second.front().offset >= it->second.front().data.size()) {
            it->second.pop_front();
          }
        }
      }

      ssize_t nsend = send(fd_, buf, (size_t)nwrite, 0);
      if (nsend < 0) {
        setError("send failed");
        return -1;
      }
    }
  }

  void send_connection_close() {
    if (!conn_) {
      return;
    }
    if (ngtcp2_conn_in_closing_period(conn_) ||
        ngtcp2_conn_in_draining_period(conn_)) {
      return;
    }
    uint8_t buf[1280];
    ngtcp2_path_storage ps;
    ngtcp2_path_storage_zero(&ps);
    ngtcp2_pkt_info pi;
    ngtcp2_ssize nwrite =
      ngtcp2_conn_write_connection_close(conn_, &ps.path, &pi, buf,
                                         sizeof(buf), &last_error_, now_ts());
    if (nwrite > 0) {
      send(fd_, buf, (size_t)nwrite, 0);
    }
  }

  void signal_wakeup() {
    if (wakeup_fds_[1] != -1) {
      uint8_t b = 1;
      write(wakeup_fds_[1], &b, 1);
    }
  }

  void drain_wakeup() {
    uint8_t buf[64];
    while (read(wakeup_fds_[0], buf, sizeof(buf)) > 0) {
    }
  }

  void cleanup() {
    ngtcp2_conn *conn_to_del = nullptr;
    void *ssl_to_free = nullptr;
    void *ssl_ctx_to_free = nullptr;
    int fd_to_close = -1;
    int wake0 = -1, wake1 = -1;
    {
      std::lock_guard<std::mutex> lock(cleanup_mutex_);
      conn_to_del = conn_;
      conn_ = nullptr;
      ssl_to_free = ssl_;
      ssl_ = nullptr;
      ssl_ctx_to_free = ssl_ctx_;
      ssl_ctx_ = nullptr;
      fd_to_close = fd_;
      fd_ = -1;
      wake0 = wakeup_fds_[0];
      wake1 = wakeup_fds_[1];
      wakeup_fds_[0] = -1;
      wakeup_fds_[1] = -1;
    }
    if (conn_to_del) {
      ngtcp2_conn_del(conn_to_del);
    }
    if (ssl_to_free) {
      wolfSSL_free(static_cast<WOLFSSL *>(ssl_to_free));
    }
    if (ssl_ctx_to_free) {
      wolfSSL_CTX_free(static_cast<WOLFSSL_CTX *>(ssl_ctx_to_free));
    }
    if (fd_to_close != -1) {
      ::close(fd_to_close);
    }
    if (wake0 != -1) {
      ::close(wake0);
    }
    if (wake1 != -1) {
      ::close(wake1);
    }
  }

  void clearError() {
    std::lock_guard<std::mutex> lock(err_mutex_);
    last_error_str_.clear();
  }

  void setError(const std::string &err) {
    std::lock_guard<std::mutex> lock(err_mutex_);
    last_error_str_ = err;
    LOGE("%s", err.c_str());
  }

  static void rand_cb(uint8_t *dest, size_t destlen,
                      const ngtcp2_rand_ctx *rand_ctx) {
    (void)rand_ctx;
    if (wolfSSL_RAND_bytes(dest, (int)destlen) != 1) {
      abort();
    }
  }

  static int get_new_connection_id_cb(ngtcp2_conn *conn, ngtcp2_cid *cid,
                                      uint8_t *token, size_t cidlen,
                                      void *user_data) {
    (void)conn;
    (void)user_data;
    if (wolfSSL_RAND_bytes(cid->data, (int)cidlen) != 1) {
      return NGTCP2_ERR_CALLBACK_FAILURE;
    }
    cid->datalen = cidlen;
    if (wolfSSL_RAND_bytes(token, NGTCP2_STATELESS_RESET_TOKENLEN) != 1) {
      return NGTCP2_ERR_CALLBACK_FAILURE;
    }
    return 0;
  }

  static int extend_max_local_streams_bidi_cb(ngtcp2_conn *conn,
                                              uint64_t max_streams,
                                              void *user_data) {
    (void)conn;
    (void)max_streams;
    (void)user_data;
    return 0;
  }

  static int recv_stream_data_cb(ngtcp2_conn *conn, uint32_t flags,
                                 int64_t stream_id, uint64_t offset,
                                 const uint8_t *data, size_t datalen,
                                 void *user_data, void *stream_user_data) {
    (void)conn;
    (void)offset;
    (void)stream_user_data;
    auto *client = static_cast<QuicClient *>(user_data);
    return client->on_recv_stream_data(flags, stream_id, data, datalen);
  }

  static int acked_stream_data_offset_cb(ngtcp2_conn *conn, int64_t stream_id,
                                         uint64_t offset, uint64_t datalen,
                                         void *user_data,
                                         void *stream_user_data) {
    (void)conn;
    (void)stream_id;
    (void)offset;
    (void)datalen;
    (void)user_data;
    (void)stream_user_data;
    return 0;
  }

  static int stream_close_cb(ngtcp2_conn *conn, uint32_t flags,
                             int64_t stream_id, uint64_t app_error_code,
                             void *user_data, void *stream_user_data) {
    (void)conn;
    (void)flags;
    (void)app_error_code;
    (void)stream_user_data;
    auto *client = static_cast<QuicClient *>(user_data);
    std::lock_guard<std::mutex> lock(client->stream_mutex_);
    auto it = client->streams_.find(stream_id);
    if (it != client->streams_.end()) {
      it->second.closed = true;
    }
    return 0;
  }

  static int handshake_completed_cb(ngtcp2_conn *conn, void *user_data) {
    (void)conn;
    auto *client = static_cast<QuicClient *>(user_data);
    return client->on_handshake_completed();
  }

 public:
  const std::string &resolved_address() const { return resolved_address_; }

 private:
  std::string host_;
  std::string connect_addr_;
  uint16_t port_;
  std::string resolved_address_;

  int fd_;
  struct sockaddr_storage remote_addr_;
  socklen_t remote_addrlen_;
  struct sockaddr_storage local_addr_;
  socklen_t local_addrlen_;

  WOLFSSL_CTX *ssl_ctx_;
  WOLFSSL *ssl_;
  ngtcp2_conn *conn_;
  ngtcp2_crypto_conn_ref conn_ref_;
  ngtcp2_ccerr last_error_;

  std::thread worker_;
  std::atomic<bool> running_;
  std::atomic<bool> connected_;
  std::atomic<bool> close_requested_;

  int wakeup_fds_[2];

  std::mutex state_mutex_;
  std::condition_variable cv_state_;

  std::mutex stream_mutex_;
  std::map<int64_t, StreamState> streams_;

  std::mutex out_mutex_;
  std::map<int64_t, std::deque<OutgoingChunk>> outgoing_;

  mutable std::mutex err_mutex_;
  std::string last_error_str_;

  std::mutex cleanup_mutex_;
};

static std::map<jlong, std::unique_ptr<QuicClient>> connections;
static std::mutex connections_mutex;
static jlong next_handle = 1;

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeCreateConnection(
    JNIEnv *env, jobject thiz, jstring host, jint port) {
  const char *host_str = env->GetStringUTFChars(host, nullptr);
  if (!host_str) {
    return 0;
  }
  std::string host_cpp(host_str);
  env->ReleaseStringUTFChars(host, host_str);

  auto client = std::make_unique<QuicClient>(host_cpp, (uint16_t)port);
  std::lock_guard<std::mutex> lock(connections_mutex);
  jlong handle = next_handle++;
  connections[handle] = std::move(client);
  return handle;
}

JNIEXPORT jlong JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeCreateConnectionWithAddress(
    JNIEnv *env, jobject thiz, jstring hostnameForTls, jstring connectAddress, jint port) {
  const char *tls_str = env->GetStringUTFChars(hostnameForTls, nullptr);
  const char *addr_str = env->GetStringUTFChars(connectAddress, nullptr);
  if (!tls_str || !addr_str) {
    if (tls_str) env->ReleaseStringUTFChars(hostnameForTls, tls_str);
    return 0;
  }
  std::string host_for_tls(tls_str);
  std::string connect_addr(addr_str);
  env->ReleaseStringUTFChars(hostnameForTls, tls_str);
  env->ReleaseStringUTFChars(connectAddress, addr_str);

  auto client = std::make_unique<QuicClient>(host_for_tls, connect_addr, (uint16_t)port);
  std::lock_guard<std::mutex> lock(connections_mutex);
  jlong handle = next_handle++;
  connections[handle] = std::move(client);
  return handle;
}

JNIEXPORT jint JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeConnect(
    JNIEnv *env, jobject thiz, jlong connHandle) {
  std::lock_guard<std::mutex> lock(connections_mutex);
  auto it = connections.find(connHandle);
  if (it == connections.end()) {
    return -1;
  }
  int rv = it->second->connect("mqtt");
  return rv;
}

JNIEXPORT jlong JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeOpenStream(
    JNIEnv *env, jobject thiz, jlong connHandle) {
  std::lock_guard<std::mutex> lock(connections_mutex);
  auto it = connections.find(connHandle);
  if (it == connections.end()) {
    return -1;  // Return -1 on error (0 is a valid stream ID)
  }
  return it->second->open_stream();
}

JNIEXPORT jint JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeWriteStream(
    JNIEnv *env, jobject thiz, jlong connHandle, jlong streamId, jbyteArray data) {
  std::lock_guard<std::mutex> lock(connections_mutex);
  auto it = connections.find(connHandle);
  if (it == connections.end()) {
    return -1;
  }
  jsize len = env->GetArrayLength(data);
  if (len <= 0) {
    return 0;
  }
  std::vector<uint8_t> buffer((size_t)len);
  env->GetByteArrayRegion(data, 0, len, reinterpret_cast<jbyte *>(buffer.data()));
  return it->second->write_stream((int64_t)streamId, buffer.data(),
                                  buffer.size(), false);
}

JNIEXPORT jbyteArray JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeReadStream(
    JNIEnv *env, jobject thiz, jlong connHandle, jlong streamId) {
  std::lock_guard<std::mutex> lock(connections_mutex);
  auto it = connections.find(connHandle);
  if (it == connections.end()) {
    return nullptr;
  }
  uint8_t buffer[8192];
  ssize_t nread = it->second->read_stream((int64_t)streamId, buffer, sizeof(buffer));
  if (nread <= 0) {
    return env->NewByteArray(0);
  }
  jbyteArray result = env->NewByteArray((jsize)nread);
  env->SetByteArrayRegion(result, 0, (jsize)nread, reinterpret_cast<jbyte *>(buffer));
  return result;
}

JNIEXPORT void JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeClose(
    JNIEnv *env, jobject thiz, jlong connHandle) {
  std::lock_guard<std::mutex> lock(connections_mutex);
  auto it = connections.find(connHandle);
  if (it == connections.end()) {
    return;
  }
  it->second->close();
  connections.erase(it);
}

JNIEXPORT jboolean JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeIsConnected(
    JNIEnv *env, jobject thiz, jlong connHandle) {
  std::lock_guard<std::mutex> lock(connections_mutex);
  auto it = connections.find(connHandle);
  if (it == connections.end()) {
    return JNI_FALSE;
  }
  return it->second->is_connected() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeCloseStream(
    JNIEnv *env, jobject thiz, jlong connHandle, jlong streamId) {
  std::lock_guard<std::mutex> lock(connections_mutex);
  auto it = connections.find(connHandle);
  if (it == connections.end()) {
    return -1;
  }
  return it->second->close_stream((int64_t)streamId);
}

JNIEXPORT jstring JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeGetLastError(
    JNIEnv *env, jobject thiz, jlong connHandle) {
  std::lock_guard<std::mutex> lock(connections_mutex);
  auto it = connections.find(connHandle);
  if (it == connections.end()) {
    return env->NewStringUTF("invalid connection");
  }
  return env->NewStringUTF(it->second->last_error());
}

JNIEXPORT jstring JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeGetLastResolvedAddress(
    JNIEnv *env, jobject thiz, jlong connHandle) {
  std::lock_guard<std::mutex> lock(connections_mutex);
  auto it = connections.find(connHandle);
  if (it == connections.end()) {
    return nullptr;
  }
  const std::string &addr = it->second->resolved_address();
  if (addr.empty()) {
    return nullptr;
  }
  return env->NewStringUTF(addr.c_str());
}

// Debug-build alias: Kotlin/AGP can mangle the method name to include the module suffix.
JNIEXPORT jstring JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeGetLastError_00024annadata_1capacitor_1mqtt_1quic_1debug__J(
    JNIEnv *env, jobject thiz, jlong connHandle) {
  return Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeGetLastError(env, thiz, connHandle);
}

} // extern "C"
