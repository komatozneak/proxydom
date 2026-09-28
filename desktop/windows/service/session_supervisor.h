#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

// Service-owned TUN session. Win32 is behind the interfaces below so a fake
// network can prove that Idle is emitted only after a verified restore.

enum class TunnelPhase { Idle, Connecting, Connected, Disconnecting };

enum class TunnelCode {
  None,
  ResolveFailed,
  ForeignTunnel,
  RouteFailed,
  CoreStartFailed,
  TunNotReady,
  EgressFailed,
  CleanupFailed,
  Busy,
  Protocol,
};

enum class ConnectStep {
  Start,
  Resolved,
  Pinned,
  ConfigWritten,
  Launched,
  JobAssigned,
  Resumed,
  TunReady,
  Proven,
};

struct PinPlan {
  std::string destination;
  std::uint64_t interface_luid = 0;
  unsigned long interface_index = 0;
  unsigned long physical_index = 0;
  std::string next_hop;
  unsigned long metric = 0;
};

struct OwnedAdapter {
  std::string name;
  std::string guid;
  std::uint64_t luid = 0;
  unsigned long if_index = 0;
  bool up = false;
};

struct OwnedRoute {
  std::string destination;
  int prefix_length = 0;
  std::uint64_t interface_luid = 0;
  unsigned long interface_index = 0;
};

struct RouteView {
  std::string adapter;
  bool hardware = false;
  bool up = false;
  bool own = false;
  int prefix_length = 0;
  std::uint32_t destination_host = 0;
  unsigned long metric = 0;
};

struct Ledger {
  std::int64_t generation = 0;
  TunnelPhase phase = TunnelPhase::Idle;
  unsigned long pid = 0;
  bool cleanup_verified = true;
  bool pin_intended = false;
  PinPlan pin;
  bool adapter_known = false;
  OwnedAdapter adapter;
  std::vector<OwnedRoute> routes;
  bool config_written = false;
};

struct TunnelSnapshot {
  TunnelPhase phase = TunnelPhase::Idle;
  std::int64_t generation = 0;
  TunnelCode code = TunnelCode::None;
  std::string message;
  bool cleanup_verified = true;
};

struct ConnectRequest {
  std::string uri;
  std::vector<std::string> direct_domains;
};

struct BeginResult {
  bool accepted = false;
  TunnelSnapshot snap;
};

class CancelFlag {
 public:
  void request() { flag_.store(true, std::memory_order_release); }
  bool requested() const { return flag_.load(std::memory_order_acquire); }
  void reset() { flag_.store(false, std::memory_order_release); }

 private:
  std::atomic<bool> flag_{false};
};

class RouteTable {
 public:
  virtual ~RouteTable() = default;
  virtual bool list_defaults(std::vector<RouteView>& out) = 0;
  virtual bool plan_hardware_pin(const std::string& destination, PinPlan& out) = 0;
  virtual bool add_pin(const PinPlan& pin) = 0;
  virtual bool delete_pin(const PinPlan& pin) = 0;
  virtual bool pin_absent(const PinPlan& pin) = 0;
  virtual bool delete_routes_on_luid(std::uint64_t luid) = 0;
  virtual bool routes_absent(std::uint64_t luid) = 0;
  virtual bool list_own_adapters(std::vector<OwnedAdapter>& out) = 0;
  virtual bool remove_adapter(const OwnedAdapter& adapter) = 0;
  virtual bool tun_ready(OwnedAdapter& adapter, std::vector<OwnedRoute>& halves) = 0;
  virtual bool prove_exit(unsigned long if_index,
                          const std::string& probe_ip,
                          const std::function<bool()>& cancelled) = 0;
  virtual unsigned long last_error() const = 0;
};

class EngineHost {
 public:
  virtual ~EngineHost() = default;
  virtual bool launch_suspended(unsigned long& pid) = 0;
  virtual bool assign_job() = 0;
  virtual bool resume() = 0;
  virtual bool request_stop() = 0;
  virtual bool alive() = 0;
  virtual void kill() = 0;
  virtual void release() = 0;
  virtual void stop_owned_processes() = 0;
  virtual unsigned long last_error() const = 0;
};

class NameResolver {
 public:
  virtual ~NameResolver() = default;
  virtual bool resolve_ipv4(const std::string& host, std::string& ip) = 0;
};

class SessionFiles {
 public:
  virtual ~SessionFiles() = default;
  // 1 parsed, 0 absent, -1 unreadable (the store quarantines the file).
  virtual int load(Ledger& ledger) = 0;
  virtual bool store(const Ledger& ledger) = 0;
  virtual bool clear() = 0;
  virtual bool write_config(const std::string& json) = 0;
  virtual bool erase_config() = 0;
  virtual bool config_present() = 0;
  virtual std::string legacy_pin() = 0;
  virtual void clear_legacy_pin() = 0;
};

class TunnelLog {
 public:
  virtual ~TunnelLog() = default;
  virtual void write(std::int64_t generation,
                     const std::string& event,
                     const std::string& code,
                     unsigned long win32) = 0;
};

class Sleeper {
 public:
  virtual ~Sleeper() = default;
  virtual void sleep_ms(int ms) = 0;
};

const char* phase_name(TunnelPhase phase);
const char* code_name(TunnelCode code);
std::string user_message(TunnelCode code, const std::string& extra);

// Empty when Connect may proceed. The name is the blocking adapter.
std::string active_foreign_tunnel(const std::vector<RouteView>& routes);

std::string encode_ledger(const Ledger& ledger);
bool decode_ledger(const std::string& text, Ledger& ledger);

class TunnelSupervisor {
 public:
  TunnelSupervisor(RouteTable& routes,
                   EngineHost& engine,
                   NameResolver& names,
                   SessionFiles& files,
                   TunnelLog& log,
                   Sleeper& sleeper);

  void set_observer(std::function<void(const TunnelSnapshot&)> observer);
  void set_hook(std::function<void(ConnectStep)> hook);

  BeginResult begin_connect();
  TunnelSnapshot run_connect(const ConnectRequest& request, CancelFlag& cancel);
  TunnelSnapshot disconnect(CancelFlag& cancel);
  TunnelSnapshot watchdog(CancelFlag& cancel);
  TunnelSnapshot reconcile(CancelFlag& cancel);
  TunnelSnapshot snapshot() const;
  // Copy. Callers on the session thread may use it after a supervisor call returns.
  Ledger ledger_copy() const;

 private:
  bool stop_requested(ConnectStep step, CancelFlag& cancel);
  bool restore_resources();
  TunnelSnapshot finish(TunnelCode code, const std::string& message, bool quiet);
  TunnelSnapshot publish(TunnelCode code, const std::string& message, bool cleanup_verified);
  void remember(const std::function<void()>& change);

  RouteTable& routes_;
  EngineHost& engine_;
  NameResolver& names_;
  SessionFiles& files_;
  TunnelLog& log_;
  Sleeper& sleeper_;
  mutable std::mutex ledger_mu_;
  Ledger ledger_;
  TunnelSnapshot published_;
  std::function<void(const TunnelSnapshot&)> observer_;
  std::function<void(ConnectStep)> hook_;
};
