#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <vector>

#include "flow_probe.h"
#include "protocol.h"

// Service-owned TUN session. Win32 is behind the interfaces below so a fake
// network can prove that Idle is emitted only after a verified restore.

enum class TunnelPhase { Idle, Connecting, Connected, Disconnecting };

enum class TunnelCode {
  None,
  ResolveFailed,
  ForeignTunnel,
  RouteFailed,
  CoreStartFailed,
  KeyProbeFailed,
  TunNotReady,
  EgressFailed,
  CoreExited,
  TunInitTimeout,
  EgressTimeout,
  AuthRejected,
  InvalidProfile,
  CleanupFailed,
  Busy,
  Protocol,
};

enum class ConnectStep {
  Start,
  Resolved,
  ProbeConfigWritten,
  ProbeLaunched,
  ProbePassed,
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
  std::string ipv4;  // empty until the engine has assigned the address
  // Diagnostics. A route into an adapter Windows treats as disconnected is
  // accepted by the route table and then refused by connect().
  unsigned long media_state = 0;  // MediaConnectState as reported by the adapter
  unsigned long dad_state = 0;    // DadState of the first IPv4 address
};

// Where Windows would actually send a packet. A route row that exists but
// cannot be used is indistinguishable from no route at all at connect() time,
// which returns the same host-unreachable either way, so ask the stack instead
// of inferring from the table we just wrote.
struct RouteLookup {
  std::string next_hop;
  std::string source;
  std::uint64_t interface_luid = 0;
  unsigned long interface_index = 0;
  int prefix_length = 0;
};

// The engine opens the wintun adapter and assigns the address afterwards, and
// Windows reports an address-less adapter as up. A canary route into such an
// adapter fails immediately, so "up" alone is not ready: wait for the address
// the engine was told to set.
//
// The address alone is not enough either. Windows reports it as
// IpDadStateTentative while it checks for a duplicate, and a route into an
// adapter whose only address is tentative is accepted by the route table and
// then refused by connect(), which answers host unreachable exactly as it does
// when no route exists at all. Measured on the owner's machine: dad=1 together
// with GetBestRoute2 returning ERROR_NOT_FOUND for a canary whose /32 row was
// present. Readiness therefore requires Preferred.
constexpr unsigned long kIpDadStateTentative = 1;
constexpr unsigned long kIpDadStatePreferred = 4;

inline bool tun_adapter_ready(const OwnedAdapter& adapter) {
  return adapter.name == kTunName && adapter.up && adapter.luid != 0 &&
         adapter.if_index != 0 && adapter.ipv4 == kTunIpv4 &&
         adapter.dad_state == kIpDadStatePreferred;
}

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
  std::vector<std::string> force_proxy_domains;
  bool udp_direct = false;
};

struct BeginResult {
  bool accepted = false;
  TunnelSnapshot snap;
};

// One live clash api connection, as last seen.
//
// The api reports each connection's own cumulative counters, so a session total
// has to be the sum of per-id deltas. Adding the raw counters instead re-counts
// every live connection's entire history on every poll, which is what made the
// journal report gigabytes for a lobby that never moved a packet.
struct FlowLive {
  std::string key;  // "network:chain"
  std::uint64_t upload = 0;
  std::uint64_t download = 0;
};

// What one "network:chain" has done about silence, since the last rate line.
//
// The two figures are per window, not for the session. A session-long worst case
// is set once and then cannot answer "was there a dip just now?" — it went blind
// after the first lull of the session and stayed blind for the rest of it. The
// window is the unit a person means by "did it just stutter", so it is the unit
// the stall is measured in. The session record survives in worst_quiet_ms, but
// only as history.
struct FlowStall {
  bool seeded = false;        // first sighting only sets the baseline
  std::uint64_t running_ms = 0;  // lull in progress, not yet closed
  std::uint64_t worst_ms = 0;    // longest lull that ended inside the window
  std::uint64_t count = 0;       // how many lulls ended inside the window
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
  // Adapter is up. Capture routes are not required yet.
  virtual bool find_own_adapter(OwnedAdapter& adapter) = 0;
  // Broker-owned 0.0.0.0/1, 128.0.0.0/1, ::/1, and 8000::/1. Not sing-box.
  virtual bool install_capture(const OwnedAdapter& adapter, std::vector<OwnedRoute>& routes) = 0;
  // On-link /32 through the TUN. The default route is still untouched.
  virtual bool add_canary(const OwnedAdapter& adapter, const std::string& ip, OwnedRoute& route) = 0;
  virtual bool delete_canary(const OwnedRoute& route) = 0;
  // Follows the routing table. No IP_UNICAST_IF bind.
  virtual bool fetch_canary(const std::string& ip, const std::function<bool()>& cancelled) = 0;
  // Which interface the stack picks for this address, and its error when it
  // picks none. Answers "is the canary route usable" without guessing.
  virtual bool lookup_route(const std::string& ip, RouteLookup& out) = 0;
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
  // Empty after a successful start. A failure name is safe to print.
  virtual const char* start_stage() const = 0;
  virtual unsigned long exit_code() const = 0;
  virtual std::string output_tail() const = 0;
};

class NameResolver {
 public:
  virtual ~NameResolver() = default;
  virtual bool resolve_ipv4(const std::string& host, std::string& ip) = 0;
};

class ConnectivityProbe {
 public:
  virtual ~ConnectivityProbe() = default;
  virtual bool pick_loopback_port(unsigned short& port) = 0;
  virtual bool prove_socks(unsigned short port,
                           const std::string& target_ip,
                           const std::function<bool()>& cancelled) = 0;
  virtual unsigned long last_error() const = 0;
  // Empty after success. A failure name is a literal the service log can print.
  virtual const char* failure_stage() const = 0;
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
  virtual unsigned long last_error() const { return 0; }
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

// What the adapter wait can actually see. It is not a Win32 from WintunCreateAdapter:
// sing-box creates the interface, and this process only observes the name afterward.
struct TunWaitView {
  bool process_alive = false;
  unsigned long process_exit = 0;
  std::string engine_text;
  bool list_ok = false;
  unsigned long list_error = 0;
  std::vector<OwnedAdapter> adapters;
};

struct TunWaitClass {
  const char* code = "adapter_not_found";
  unsigned long win32 = 0;
};

// One service-log code for the blind tun_init_timeout line. Does not decide Connect.
TunWaitClass classify_tun_wait(const TunWaitView& view);

// Empty when Connect may proceed. The name is the blocking adapter.
std::string active_foreign_tunnel(const std::vector<RouteView>& routes);

// Why the broker is looking at the tunnel again.
//
// The pipe is a channel, not a lease. The service owns the session and the
// next window re-attaches to it with `hello`, so a closed client channel is
// listed here as a reason that leaves the tunnel alone. Reading a lost pipe as
// a stop request is what made the tunnel die with the window, and what let a
// flapping pipe kill a live session.
enum class TeardownReason {
  ClientGone,
  Explicit,
  ServiceStop,
  Suspend,
  Lost,
};

// The single rule: only a lost client keeps the tunnel running.
bool tunnel_should_stop(TeardownReason reason);
const char* reason_name(TeardownReason reason);

std::string encode_ledger(const Ledger& ledger);
bool decode_ledger(const std::string& text, Ledger& ledger);

class TunnelSupervisor {
 public:
  TunnelSupervisor(RouteTable& routes,
                   EngineHost& engine,
                   NameResolver& names,
                   ConnectivityProbe& probe,
                   SessionFiles& files,
                   TunnelLog& log,
                   Sleeper& sleeper);

  void set_observer(std::function<void(const TunnelSnapshot&)> observer);
  void set_ready_observer(std::function<void(std::int64_t)> observer);
  void set_hook(std::function<void(ConnectStep)> hook);
  // Builds the loopback client for the engine's clash api. Left unset, the
  // session starts with no controller and the journal carries no counters.
  void set_flow_factory(
      std::function<std::unique_ptr<FlowProbe>(unsigned short, const std::string&)> factory);
  // Sample and summary clocks. Production leaves it unset and the supervisor
  // reads the steady clock; a test drives it to place windows by hand.
  void set_clock(std::function<std::uint64_t()> clock);
  // Medium controller reports gate 3. A mismatched generation is ignored.
  void note_user_proof(bool ok, std::int64_t generation);
  // Unit tests skip the real controller. Production leaves this false.
  void accept_user_proof_for_tests(bool enabled);

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
  bool stop_engine_only();
  bool restore_resources();
  bool wait_user_proof(std::int64_t generation, CancelFlag& cancel);
  TunnelSnapshot finish(TunnelCode code, const std::string& message, bool quiet);
  TunnelSnapshot publish(TunnelCode code, const std::string& message, bool cleanup_verified);
  void remember(const std::function<void()>& change);
  // outcome nullptr starts the step. "ok" closes it. A start without ok is the hang.
  void gate(const char* step, const char* outcome);
  // Names the adapter wait in the service log. Connect still ends as tun_init_timeout.
  void note_tun_timeout();
  // Reads the engine's connection list and folds it into the running totals.
  void sample_flows();
  // Per chain, for the window just closed: bytes per second, the longest lull
  // that ended inside it, how many lulls that was, and the live connection
  // count. Every dip is therefore visible the moment it happens, and no earlier
  // one can mask a later one.
  void emit_flow_rate();
  void emit_flow_summary(const char* event);

  RouteTable& routes_;
  EngineHost& engine_;
  NameResolver& names_;
  ConnectivityProbe& probe_;
  SessionFiles& files_;
  TunnelLog& log_;
  Sleeper& sleeper_;
  mutable std::mutex ledger_mu_;
  Ledger ledger_;
  TunnelSnapshot published_;
  std::function<void(const TunnelSnapshot&)> observer_;
  std::function<void(std::int64_t)> ready_observer_;
  std::function<void(ConnectStep)> hook_;
  std::function<std::unique_ptr<FlowProbe>(unsigned short, const std::string&)> flow_factory_;
  std::unique_ptr<FlowProbe> flows_;
  std::function<std::uint64_t()> clock_;
  // Running totals per "network:chain", and the last seen counters per
  // connection id. The journal answers "did game UDP leave direct" from the
  // former and "did the flow stall" from the latter.
  std::map<std::string, FlowLive> flow_live_;
  std::map<std::string, std::uint64_t> flow_up_;
  std::map<std::string, std::uint64_t> flow_down_;
  // Bytes banked since the last flow_rate line, so a rate is a measured value.
  std::map<std::string, std::uint64_t> rate_up_;
  std::map<std::string, std::uint64_t> rate_down_;
  // Silence, per chain. Silences are counted per chain because "nothing moved"
  // for the whole session is not the question: what matters is whether the chain
  // carrying the game went quiet while some other chain kept dribbling bytes.
  std::map<std::string, FlowStall> stalls_;
  std::uint64_t flow_window_ms_ = 0;
  std::uint64_t flow_worst_quiet_ms_ = 0;
  std::set<std::string> flow_announced_;
  std::uint64_t flow_last_sample_ms_ = 0;
  std::uint64_t flow_last_summary_ms_ = 0;
  bool flow_api_reported_ = false;
  bool flow_untracked_reported_ = false;
  std::int64_t proof_generation_ = 0;
  int proof_result_ = 0;
  bool test_user_proof_ = false;
};
