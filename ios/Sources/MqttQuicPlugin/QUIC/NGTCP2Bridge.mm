#include "NGTCP2Bridge.h"

#include <ngtcp2/ngtcp2.h>
#include <ngtcp2/ngtcp2_crypto.h>
#include <ngtcp2/ngtcp2_crypto_quictls.h>

#include <openssl/ssl.h>
#include <openssl/rand.h>
#include <openssl/err.h>

#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cstdarg>
#include <cstdlib>
#include <cstdio>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

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
  QuicClient()
      : fd_(-1),
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

  int connect(const std::string &host, uint16_t port, const std::string &alpn) {
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      if (connected_) {
        return 0;
      }
    }
    clearError();

    if (init_socket(host, port) != 0) {
      return -1;
    }
    if (init_tls(host, alpn) != 0) {
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
    return (ssize_t)n;
  }

  int close_stream(int64_t stream_id) {
    if (!conn_) {
      return 0;
    }
    int rv = ngtcp2_conn_shutdown_stream_write(conn_, stream_id, 0);
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
    fprintf(stderr, "ngtcp2: handshake completed\n");
    cv_state_.notify_all();
    return 0;
  }

 private:
  static ngtcp2_conn *get_conn(ngtcp2_crypto_conn_ref *conn_ref) {
    auto *client = static_cast<QuicClient *>(conn_ref->user_data);
    return client->conn_;
  }

  int init_socket(const std::string &host, uint16_t port) {
    struct addrinfo hints;
    struct addrinfo *res = nullptr;
    memset(&hints, 0, sizeof(hints));
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_family = AF_UNSPEC;

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%u", port);
    int rv = getaddrinfo(host.c_str(), port_str, &hints, &res);
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
      if (connect(fd, rp->ai_addr, rp->ai_addrlen) == 0) {
        memcpy(&remote_addr_, rp->ai_addr, rp->ai_addrlen);
        remote_addrlen_ = (socklen_t)rp->ai_addrlen;
        break;
      }
      close(fd);
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
      close(fd);
      return -1;
    }

    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0) {
      fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }

    fd_ = fd;
    return 0;
  }

  int init_tls(const std::string &host, const std::string &alpn) {
    if (ngtcp2_crypto_quictls_init() != 0) {
      setError("ngtcp2_crypto_quictls_init failed");
      return -1;
    }
    ssl_ctx_ = SSL_CTX_new(TLS_client_method());
    if (!ssl_ctx_) {
      setError("SSL_CTX_new failed");
      return -1;
    }
    if (ngtcp2_crypto_quictls_configure_client_context(ssl_ctx_) != 0) {
      setError("ngtcp2_crypto_quictls_configure_client_context failed");
      return -1;
    }
    SSL_CTX_set_verify(ssl_ctx_, SSL_VERIFY_PEER, nullptr);

    ssl_ = SSL_new(ssl_ctx_);
    if (!ssl_) {
      setError("SSL_new failed");
      return -1;
    }
    SSL_set_app_data(ssl_, &conn_ref_);
    SSL_set_connect_state(ssl_);

    std::string alpn_vec;
    alpn_vec.push_back(static_cast<char>(alpn.size()));
    alpn_vec.append(alpn);
    SSL_set_alpn_protos(ssl_,
                        reinterpret_cast<const unsigned char *>(alpn_vec.data()),
                        (unsigned int)alpn_vec.size());
    SSL_set_tlsext_host_name(ssl_, host.c_str());

    if (SSL_set1_host(ssl_, host.c_str()) != 1) {
      setError("SSL_set1_host failed");
      return -1;
    }

    bool ca_loaded = false;
    const char *ca_file = std::getenv("MQTT_QUIC_CA_FILE");
    const char *ca_path = std::getenv("MQTT_QUIC_CA_PATH");
    if ((ca_file && ca_file[0] != '\0') || (ca_path && ca_path[0] != '\0')) {
      if (SSL_CTX_load_verify_locations(ssl_ctx_, ca_file, ca_path) != 1) {
        setError("Failed to load CA bundle from MQTT_QUIC_CA_FILE/CA_PATH");
        return -1;
      }
      ca_loaded = true;
    }
    if (!ca_loaded) {
      if (SSL_CTX_set_default_verify_paths(ssl_ctx_) == 1) {
        ca_loaded = true;
      }
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
    params.initial_max_streams_bidi = 8;
    params.initial_max_stream_data_bidi_local = 256 * 1024;
    params.initial_max_data = 1024 * 1024;

    ngtcp2_cid dcid, scid;
    dcid.datalen = NGTCP2_MIN_INITIAL_DCIDLEN;
    if (RAND_bytes(dcid.data, (int)dcid.datalen) != 1) {
      setError("RAND_bytes failed");
      return -1;
    }
    scid.datalen = 8;
    if (RAND_bytes(scid.data, (int)scid.datalen) != 1) {
      setError("RAND_bytes failed");
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
    if (conn_) {
      ngtcp2_conn_del(conn_);
      conn_ = nullptr;
    }
    if (ssl_) {
      SSL_free(ssl_);
      ssl_ = nullptr;
    }
    if (ssl_ctx_) {
      SSL_CTX_free(ssl_ctx_);
      ssl_ctx_ = nullptr;
    }
    if (fd_ != -1) {
      close(fd_);
      fd_ = -1;
    }
    if (wakeup_fds_[0] != -1) {
      close(wakeup_fds_[0]);
      wakeup_fds_[0] = -1;
    }
    if (wakeup_fds_[1] != -1) {
      close(wakeup_fds_[1]);
      wakeup_fds_[1] = -1;
    }
  }

  void clearError() {
    std::lock_guard<std::mutex> lock(err_mutex_);
    last_error_str_.clear();
  }

  void setError(const std::string &err) {
    std::lock_guard<std::mutex> lock(err_mutex_);
    last_error_str_ = err;
    fprintf(stderr, "ngtcp2 error: %s\n", err.c_str());
  }

  static void rand_cb(uint8_t *dest, size_t destlen,
                      const ngtcp2_rand_ctx *rand_ctx) {
    (void)rand_ctx;
    if (RAND_bytes(dest, (int)destlen) != 1) {
      abort();
    }
  }

  static int get_new_connection_id_cb(ngtcp2_conn *conn, ngtcp2_cid *cid,
                                      uint8_t *token, size_t cidlen,
                                      void *user_data) {
    (void)conn;
    (void)user_data;
    if (RAND_bytes(cid->data, (int)cidlen) != 1) {
      return NGTCP2_ERR_CALLBACK_FAILURE;
    }
    cid->datalen = cidlen;
    if (RAND_bytes(token, NGTCP2_STATELESS_RESET_TOKENLEN) != 1) {
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

  static int stream_close_cb(ngtcp2_conn *conn, int64_t stream_id,
                             uint64_t app_error_code, void *user_data,
                             void *stream_user_data) {
    (void)conn;
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

 private:
  int fd_;
  struct sockaddr_storage remote_addr_;
  socklen_t remote_addrlen_;
  struct sockaddr_storage local_addr_;
  socklen_t local_addrlen_;

  SSL_CTX *ssl_ctx_;
  SSL *ssl_;
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
};

}  // namespace

extern "C" {

NGTCP2ClientHandle ngtcp2_client_create(void) { return new QuicClient(); }

void ngtcp2_client_destroy(NGTCP2ClientHandle handle) {
  if (!handle) {
    return;
  }
  auto *client = static_cast<QuicClient *>(handle);
  delete client;
}

int ngtcp2_client_connect(NGTCP2ClientHandle handle, const char *host,
                          uint16_t port, const char *alpn) {
  if (!handle || !host || !alpn) {
    return -1;
  }
  auto *client = static_cast<QuicClient *>(handle);
  return client->connect(host, port, alpn);
}

int64_t ngtcp2_client_open_stream(NGTCP2ClientHandle handle) {
  if (!handle) {
    return -1;
  }
  auto *client = static_cast<QuicClient *>(handle);
  return client->open_stream();
}

int ngtcp2_client_write_stream(NGTCP2ClientHandle handle, int64_t stream_id,
                               const uint8_t *data, size_t datalen, int fin) {
  if (!handle || (!data && datalen > 0)) {
    return -1;
  }
  auto *client = static_cast<QuicClient *>(handle);
  return client->write_stream(stream_id, data, datalen, fin != 0);
}

ssize_t ngtcp2_client_read_stream(NGTCP2ClientHandle handle, int64_t stream_id,
                                  uint8_t *buffer, size_t maxlen) {
  if (!handle || !buffer || maxlen == 0) {
    return 0;
  }
  auto *client = static_cast<QuicClient *>(handle);
  return client->read_stream(stream_id, buffer, maxlen);
}

int ngtcp2_client_close_stream(NGTCP2ClientHandle handle, int64_t stream_id) {
  if (!handle) {
    return -1;
  }
  auto *client = static_cast<QuicClient *>(handle);
  return client->close_stream(stream_id);
}

int ngtcp2_client_close(NGTCP2ClientHandle handle) {
  if (!handle) {
    return -1;
  }
  auto *client = static_cast<QuicClient *>(handle);
  return client->close();
}

int ngtcp2_client_is_connected(NGTCP2ClientHandle handle) {
  if (!handle) {
    return 0;
  }
  auto *client = static_cast<QuicClient *>(handle);
  return client->is_connected();
}

const char *ngtcp2_client_last_error(NGTCP2ClientHandle handle) {
  if (!handle) {
    return "invalid client handle";
  }
  auto *client = static_cast<QuicClient *>(handle);
  return client->last_error();
}

}  // extern "C"
