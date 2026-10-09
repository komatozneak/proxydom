#include "session_supervisor.h"

#include "log_sanitizer.h"

#include <algorithm>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

namespace {

int g_failed = 0;

void expect(bool ok, const char* label) {
  if (ok) return;
  std::cerr << "FAIL " << label << "\n";
  ++g_failed;
}

RouteView route_view(const char* name, bool hardware, int prefix, unsigned long metric, std::uint32_t dest = 0) {
  RouteView row;
  row.adapter = name;
  row.hardware = hardware;
  row.up = true;
  row.own = std::string(name) == "ProxyDomTun";
  row.prefix_length = prefix;
  row.destination_host = dest;
  row.metric = metric;
  return row;
}

class FakeRoutes : public RouteTable {
 public:
  std::vector<RouteView> defaults;
  bool defaults_ok = true;
  bool list_ok = true;
  bool use_listed = false;
  std::vector<OwnedAdapter> listed;
  int list_calls = 0;
  bool pin_present = false;
  int add_calls = 0;
  int capture_calls = 0;
  bool capture_ok = true;
  int delete_pin_failures = 0;
  bool adapter_present = false;
  bool routes_present = false;
  bool remove_ok = true;
  bool delete_routes_ok = true;
  int tun_misses = 0;
  bool prove_ok = true;
  int prove_calls = 0;
  bool canary_ok = true;
  int canary_calls = 0;
  bool canary_present = false;
  bool fetch_ok = true;
  int fetch_calls = 0;
  bool lookup_ok = true;
  int lookup_calls = 0;
  unsigned long lookup_luid = 99;
  unsigned long dad_state = kIpDadStatePreferred;
  int tentative_polls = 0;
  bool cancel_during_fetch = false;
  unsigned long hardware_index = 18;
  CancelFlag* cancel = nullptr;
  bool cancel_during_prove = false;

  bool list_defaults(std::vector<RouteView>& out) override {
    if (!defaults_ok) return false;
    out = defaults;
    return true;
  }
  bool plan_hardware_pin(const std::string& destination, PinPlan& out) override {
    out.destination = destination;
    out.interface_luid = 18;
    out.interface_index = hardware_index;
    out.physical_index = hardware_index;
    out.next_hop = "192.168.0.1";
    out.metric = 25;
    return true;
  }
  bool add_pin(const PinPlan&) override {
    ++add_calls;
    pin_present = true;
    return true;
  }
  bool delete_pin(const PinPlan&) override {
    if (delete_pin_failures > 0) {
      --delete_pin_failures;
      return false;
    }
    pin_present = false;
    return true;
  }
  bool pin_absent(const PinPlan&) override { return !pin_present; }
  bool delete_routes_on_luid(std::uint64_t) override {
    if (!delete_routes_ok) return false;
    routes_present = false;
    canary_present = false;
    return true;
  }
  bool routes_absent(std::uint64_t) override { return !routes_present; }
  bool list_own_adapters(std::vector<OwnedAdapter>& out) override {
    out.clear();
    ++list_calls;
    if (!list_ok) return false;
    // The first read is the timeout diagnosis. Later reads are restore, which
    // must see a clean list or the fake would turn a timeout into cleanup_failed.
    if (use_listed && list_calls == 1) {
      out = listed;
      return true;
    }
    if (!adapter_present) return true;
    OwnedAdapter adapter;
    adapter.name = "ProxyDomTun";
    adapter.guid = "{tun}";
    adapter.luid = 99;
    adapter.if_index = 5;
    adapter.up = true;
    adapter.ipv4 = kTunIpv4;
    adapter.dad_state = dad_state;
    out.push_back(adapter);
    return true;
  }
  bool remove_adapter(const OwnedAdapter&) override {
    if (!remove_ok) return false;
    adapter_present = false;
    routes_present = false;
    return true;
  }
  bool find_own_adapter(OwnedAdapter& adapter) override {
    if (tun_misses > 0) {
      --tun_misses;
      return false;
    }
    OwnedAdapter candidate;
    candidate.name = "ProxyDomTun";
    candidate.guid = "{tun}";
    candidate.luid = 99;
    candidate.if_index = 5;
    candidate.up = true;
    candidate.ipv4 = kTunIpv4;
    candidate.dad_state = dad_state;
    if (tentative_polls > 0) {
      --tentative_polls;
      candidate.dad_state = kIpDadStateTentative;
    }
    // Ask the same question the route table asks. A fake that simply said yes
    // would let the suite pass while the readiness rule the real adapter has to
    // satisfy went unexercised, which is exactly how the tentative address
    // stayed invisible.
    if (!tun_adapter_ready(candidate)) return false;
    adapter = candidate;
    adapter_present = true;
    return true;
  }
  bool add_canary(const OwnedAdapter& adapter, const std::string& ip, OwnedRoute& route) override {
    ++canary_calls;
    if (!canary_ok) return false;
    canary_present = true;
    route.destination = ip;
    route.prefix_length = 32;
    route.interface_luid = adapter.luid;
    route.interface_index = adapter.if_index;
    return true;
  }
  bool delete_canary(const OwnedRoute&) override {
    canary_present = false;
    return true;
  }
  bool fetch_canary(const std::string&, const std::function<bool()>& cancelled) override {
    ++fetch_calls;
    if (cancel_during_fetch && cancel != nullptr) cancel->request();
    if (cancelled && cancelled()) return false;
    return fetch_ok;
  }
  bool lookup_route(const std::string&, RouteLookup& out) override {
    ++lookup_calls;
    if (!lookup_ok) return false;
    out.interface_luid = lookup_luid;
    out.interface_index = 5;
    out.prefix_length = 32;
    out.next_hop = "0.0.0.0";
    out.source = "198.18.0.1";
    return true;
  }
  bool install_capture(const OwnedAdapter& adapter, std::vector<OwnedRoute>& routes) override {
    ++capture_calls;
    routes.clear();
    if (!capture_ok) return false;
    routes_present = true;
    const char* destinations[] = {"0.0.0.0", "128.0.0.0", "::", "8000::"};
    for (const char* destination : destinations) {
      OwnedRoute route;
      route.destination = destination;
      route.prefix_length = 1;
      route.interface_luid = adapter.luid;
      route.interface_index = adapter.if_index;
      routes.push_back(route);
    }
    return true;
  }
  bool tun_ready(OwnedAdapter& adapter, std::vector<OwnedRoute>& halves) override {
    if (!adapter_present || !routes_present) return false;
    adapter.name = "ProxyDomTun";
    adapter.guid = "{tun}";
    adapter.luid = 99;
    adapter.if_index = 5;
    adapter.up = true;
    OwnedRoute low;
    low.destination = "0.0.0.0";
    low.prefix_length = 1;
    low.interface_luid = 99;
    low.interface_index = 5;
    OwnedRoute high = low;
    high.destination = "128.0.0.0";
    halves = {low, high};
    return true;
  }
  bool prove_exit(unsigned long, const std::string&, const std::function<bool()>& cancelled) override {
    ++prove_calls;
    if (cancel_during_prove && cancel != nullptr) cancel->request();
    if (cancelled && cancelled()) return false;
    return prove_ok;
  }
  unsigned long last_error() const override { return 0; }
};

class FakeEngine : public EngineHost {
 public:
  bool running = false;
  bool job_ok = true;
  int fail_assign_on = 0;
  bool graceful = false;
  bool unkillable = false;
  int kill_calls = 0;
  int resume_calls = 0;
  int assign_calls = 0;
  int launch_calls = 0;
  bool die_after_resume = false;
  bool fail_launch = false;
  unsigned long launch_error = 87;
  unsigned long exit_status = 0;
  unsigned long last_err = 0;
  const char* stage_name = "";
  std::string tail;

  bool launch_suspended(unsigned long& pid) override {
    ++launch_calls;
    if (fail_launch) {
      last_err = launch_error;
      stage_name = "core_create_process_failed";
      return false;
    }
    running = true;
    pid = 42;
    last_err = 0;
    stage_name = "";
    return true;
  }
  bool assign_job() override {
    ++assign_calls;
    if (!(job_ok && assign_calls != fail_assign_on)) {
      last_err = 5;
      stage_name = "core_job_assign_failed";
      return false;
    }
    return true;
  }
  bool resume() override {
    ++resume_calls;
    if (die_after_resume) {
      running = false;
      exit_status = 1;
    }
    return true;
  }
  bool request_stop() override {
    if (!graceful) return false;
    running = false;
    return true;
  }
  bool alive() override { return running; }
  void kill() override {
    ++kill_calls;
    if (!unkillable) running = false;
  }
  void release() override {}
  void stop_owned_processes() override {
    if (!unkillable) running = false;
  }
  unsigned long last_error() const override { return last_err; }
  const char* start_stage() const override { return stage_name; }
  unsigned long exit_code() const override { return exit_status; }
  std::string output_tail() const override { return tail; }
};

class FakeNames : public NameResolver {
 public:
  bool fail = false;
  // The server host resolves first and the probe host second, so failing every
  // call can never reach the probe path. fail_on_call names the call to fail.
  int calls = 0;
  int fail_on_call = 0;
  bool resolve_ipv4(const std::string& host, std::string& ip) override {
    ++calls;
    if (fail) return false;
    if (fail_on_call != 0 && calls == fail_on_call) return false;
    ip = host == "cp.cloudflare.com" ? "1.1.1.1" : "203.0.113.10";
    return true;
  }
};

class FakeProbe : public ConnectivityProbe {
 public:
  bool ok = true;
  int calls = 0;
  CancelFlag* cancel = nullptr;
  bool cancel_during = false;
  const char* stage = "socks_unreachable";
  unsigned long error = 10061;

  bool pick_loopback_port(unsigned short& port) override {
    port = 17890;
    return true;
  }
  bool prove_socks(unsigned short,
                   const std::string&,
                   const std::function<bool()>& cancelled) override {
    ++calls;
    if (cancel_during && cancel != nullptr) cancel->request();
    return ok && (!cancelled || !cancelled());
  }
  unsigned long last_error() const override { return ok ? 0 : error; }
  const char* failure_stage() const override { return ok ? "" : stage; }
};

class FakeFiles : public SessionFiles {
 public:
  bool has_ledger = false;
  Ledger stored;
  bool config = false;
  std::string config_body;
  bool erase_ok = true;
  std::string legacy;

  int load(Ledger& ledger) override {
    if (!has_ledger) return 0;
    ledger = stored;
    return 1;
  }
  bool store(const Ledger& ledger) override {
    stored = ledger;
    has_ledger = true;
    return true;
  }
  bool clear() override {
    has_ledger = false;
    stored = Ledger{};
    return true;
  }
  bool write_config(const std::string& json) override {
    config = true;
    config_body = json;
    return true;
  }
  bool erase_config() override {
    if (!erase_ok) return false;
    config = false;
    config_body.clear();
    return true;
  }
  bool config_present() override { return config; }
  std::string legacy_pin() override { return legacy; }
  void clear_legacy_pin() override { legacy.clear(); }
};

class FakeLog : public TunnelLog {
 public:
  struct Line {
    std::string event;
    std::string code;
    unsigned long win32 = 0;
  };
  std::vector<Line> lines;
  void write(std::int64_t, const std::string& event, const std::string& code, unsigned long win32) override {
    lines.push_back(Line{event, code, win32});
  }
  int index_of(const std::string& event, const std::string& code) const {
    for (int i = 0; i < static_cast<int>(lines.size()); ++i) {
      if (lines[static_cast<std::size_t>(i)].event == event &&
          lines[static_cast<std::size_t>(i)].code == code) {
        return i;
      }
    }
    return -1;
  }
};

class FakeSleep : public Sleeper {
 public:
  void sleep_ms(int) override {}
};

// Stands in for the engine's clash api. The rows are what the owner reads the
// session verdict from: a game's UDP landing on "direct" means it left the
// tunnel on the physical interface, "proxy" means it is still being carried.
struct FlowState {
  bool reachable = true;
  int polls = 0;
  std::vector<FlowRow> rows;
  std::size_t untracked = 0;
  // One row set per poll. When set it wins over `rows`, so a test can make the
  // counters advance the way the real api does: cumulative, per connection.
  std::vector<std::vector<FlowRow>> script;
};

// The supervisor owns the probe for the length of a session, so the test keeps
// its own handle through shared state rather than through the object itself.
class FakeFlows : public FlowProbe {
 public:
  explicit FakeFlows(std::shared_ptr<FlowState> state) : state_(std::move(state)) {}
  bool poll(FlowSample& out) override {
    ++state_->polls;
    if (!state_->reachable) return false;
    out.rows = state_->rows;
    out.untracked = state_->untracked;
    const std::size_t index = static_cast<std::size_t>(state_->polls - 1);
    if (!state_->script.empty() && index < state_->script.size()) out.rows = state_->script[index];
    return true;
  }
  unsigned long last_error() const override { return 0; }

 private:
  std::shared_ptr<FlowState> state_;
};

FlowRow flow_row(std::string id, std::string network, std::string chain, std::string destination,
                 std::uint64_t up, std::uint64_t down) {
  FlowRow row;
  row.id = std::move(id);
  row.network = std::move(network);
  row.chain = std::move(chain);
  row.destination = std::move(destination);
  row.upload = up;
  row.download = down;
  return row;
}

struct Harness {
  FakeRoutes routes;
  FakeEngine engine;
  FakeNames names;
  FakeProbe probe;
  FakeFiles files;
  FakeLog log;
  FakeSleep sleeper;
  TunnelSupervisor supervisor;
  CancelFlag cancel;

  Harness() : supervisor(routes, engine, names, probe, files, log, sleeper) {
    routes.cancel = &cancel;
    probe.cancel = &cancel;
    supervisor.accept_user_proof_for_tests(true);
  }

  ConnectRequest request() const {
    ConnectRequest req;
    req.uri = "hy2://secret-password@cdn.example:443?obfs=salamander&obfs-password=hide";
    req.direct_domains = {"lan.example"};
    return req;
  }

  TunnelSnapshot connect() {
    expect(supervisor.begin_connect().accepted, "begin");
    return supervisor.run_connect(request(), cancel);
  }
};

void test_route_policy() {
  expect(active_foreign_tunnel({route_view("happ-xray", false, 0, 0), route_view("Ethernet", true, 0, 25)}) ==
             "happ-xray",
         "happ beats ethernet");
  expect(active_foreign_tunnel({route_view("Radmin VPN", false, 0, 9256), route_view("Ethernet", true, 0, 25)}).empty(),
         "radmin behind ethernet is not the default");
  expect(active_foreign_tunnel({route_view("Radmin VPN", false, 0, 9256)}) == "Radmin VPN",
         "only virtual default blocks");
  expect(active_foreign_tunnel({route_view("happ-xray", false, 1, 0, 0),
                                 route_view("happ-xray", false, 1, 0, 0x80000000u)}) == "happ-xray",
         "split default blocks");
  expect(active_foreign_tunnel({route_view("ProxyDomTun", false, 1, 0, 0),
                                 route_view("ProxyDomTun", false, 1, 0, 0x80000000u)})
             .empty(),
         "own halves are not foreign");
}

void test_slash_port_connects_and_junk_does_not_launch() {
  Harness slash;
  ConnectRequest req;
  req.uri = "hy2://secret-password@cdn.example:443/?sni=cdn.example&obfs=salamander&obfs-password=hide";
  expect(slash.supervisor.begin_connect().accepted, "slash begin");
  const auto ok = slash.supervisor.run_connect(req, slash.cancel);
  expect(ok.phase == TunnelPhase::Connected, "slash after port still connects");
  expect(slash.files.config_body.find("server_ports") == std::string::npos, "slash config has no port range");

  Harness junk;
  ConnectRequest bad;
  bad.uri = "hy2://secret-password@cdn.example:443abc?sni=cdn.example";
  expect(junk.supervisor.begin_connect().accepted, "junk begin");
  const auto snap = junk.supervisor.run_connect(bad, junk.cancel);
  expect(snap.code == TunnelCode::InvalidProfile, "junk port code");
  expect(snap.message == "Неверный порт сервера", "junk port text");
  expect(junk.engine.launch_calls == 0, "junk port does not start the engine");
  expect(junk.log.index_of("profile_parse_failed", "443abc") >= 0, "junk port is logged");
}

void test_foreign_blocks_before_pin() {
  Harness harness;
  harness.routes.defaults = {route_view("happ-xray", false, 0, 0), route_view("Ethernet", true, 0, 25)};
  const auto snap = harness.connect();
  expect(snap.phase == TunnelPhase::Idle, "foreign ends idle");
  expect(snap.code == TunnelCode::ForeignTunnel, "foreign code");
  expect(snap.cleanup_verified, "foreign did not need cleanup");
  expect(snap.message == "Обнаружен активный туннель", "foreign caption");
  expect(snap.message.find("happ") == std::string::npos, "foreign caption has no program");
  expect(snap.message.find("Happ") == std::string::npos, "foreign caption has no Happ");
  const int gate = harness.log.index_of("gate", "foreign_tunnel");
  const int idle = harness.log.index_of("idle", "foreign_tunnel");
  expect(gate >= 0 && idle > gate, "foreign gate before idle");
  expect(harness.log.index_of("foreign_adapter", "happ-xray") > gate, "adapter stays in the log");
  expect(harness.log.index_of("gate", "foreign_tunnel=ok") < 0, "foreign refusal has no ok");
  expect(harness.routes.add_calls == 0, "foreign adds no pin");
  expect(harness.routes.capture_calls == 0, "foreign installs no capture");
  expect(!harness.files.config, "foreign writes no config");
}

void test_radmin_allows_connect() {
  Harness harness;
  harness.routes.defaults = {route_view("Radmin VPN", false, 0, 9256), route_view("Ethernet", true, 0, 25)};
  const auto snap = harness.connect();
  bool saw_timeout = false;
  for (const auto& line : harness.log.lines) {
    if (line.event == "tun_init_timeout") saw_timeout = true;
  }
  expect(!saw_timeout, "successful connect does not time out the adapter");
  expect(snap.phase == TunnelPhase::Connected, "radmin does not block");
  expect(harness.probe.calls == 0, "connect does not open a socks probe");
  expect(harness.routes.canary_calls == 1, "canary is installed before capture");
  expect(!harness.routes.canary_present, "canary is removed after proof");
  expect(harness.routes.capture_calls == 1, "broker installs the capture routes");
  expect(harness.files.config_body.find("\"auto_route\":false") != std::string::npos, "engine auto_route is off");
  expect(harness.supervisor.ledger_copy().routes.size() == 4, "ledger records four capture prefixes");
  expect(snap.cleanup_verified == false, "connected is not a restore");
  expect(harness.files.config_body.find("secret-password") != std::string::npos, "engine config keeps the secret");
  expect(encode_ledger(harness.supervisor.ledger_copy()).find("secret-password") == std::string::npos,
         "ledger has no password");
  expect(encode_ledger(harness.supervisor.ledger_copy()).find("hide") == std::string::npos, "ledger has no obfs secret");
}

void test_bad_key_never_mutates_routes() {
  Harness harness;
  harness.engine.die_after_resume = true;
  harness.engine.tail = "listen failed \"password\":\"secret-password\"";
  const auto snap = harness.connect();
  expect(snap.code == TunnelCode::CoreExited, "dead engine is core_exited");
  expect(snap.message == "Сбой локальной службы туннеля", "dead engine text");
  expect(snap.phase == TunnelPhase::Idle && snap.cleanup_verified, "dead engine restores");
  expect(harness.probe.calls == 0, "dead engine does not open socks");
  expect(harness.routes.add_calls == 0, "dead engine adds no pin");
  expect(harness.routes.capture_calls == 0, "dead engine installs no capture");
  bool leaked = false;
  bool saw_exit = false;
  for (const auto& line : harness.log.lines) {
    if (line.code.find("secret-password") != std::string::npos) leaked = true;
    if (line.event == "core_exited") saw_exit = true;
  }
  expect(saw_exit, "core exit is logged");
  expect(!leaked, "engine log drops the password");
}

// A line this platform cannot carry is a refusal, not a crash. The engine names
// it and leaves before a core exists; reporting that as a dead service sends the
// person looking for a bug in the client instead of at their own line.
void test_a_refused_transport_is_not_a_crash() {
  Harness harness;
  harness.engine.die_after_resume = true;
  harness.engine.tail = "error transport_unsupported";
  const auto snap = harness.connect();
  expect(snap.code == TunnelCode::TransportUnsupported, "the engine's name reaches the code");
  expect(snap.message == "Этот транспорт не поддержан на этой платформе",
         "the caption is the refusal, not a service fault");
  expect(snap.phase == TunnelPhase::Idle && snap.cleanup_verified, "a refusal restores");
  expect(harness.routes.add_calls == 0, "a refusal adds no pin");
  expect(harness.routes.capture_calls == 0, "a refusal installs no capture");
  bool named_refusal = false;
  bool kept_words = false;
  for (const auto& line : harness.log.lines) {
    if (line.event == "line_refused" && line.code == "transport_unsupported") named_refusal = true;
    if (line.event == "core_exited" && line.code.find("transport_unsupported") != std::string::npos) {
      kept_words = true;
    }
  }
  expect(named_refusal, "the journal names the refusal, so it is not invisible");
  expect(kept_words, "the engine's own words are still kept");
}

// Reality is refused for its security, not its transport. One name for both
// would tell the person to change the wrong half of their line.
void test_a_refused_security_keeps_its_own_name() {
  Harness harness;
  harness.engine.die_after_resume = true;
  harness.engine.tail = "error security_unsupported";
  const auto snap = harness.connect();
  expect(snap.code == TunnelCode::SecurityUnsupported, "security is named apart from transport");
  expect(snap.message == "Этот способ защиты не поддержан на этой платформе", "security caption");
}

// The list of names the broker understands is closed. A word it has not agreed
// on stays a plain core exit: inventing a name for it would be worse than the
// honest generic one.
void test_an_unknown_word_is_still_a_core_exit() {
  Harness harness;
  harness.engine.die_after_resume = true;
  harness.engine.tail = "error something_new_the_engine_grew";
  const auto snap = harness.connect();
  expect(snap.code == TunnelCode::CoreExited, "an unagreed word stays a core exit");
  expect(snap.message == "Сбой локальной службы туннеля", "unknown exit keeps the service caption");
}

void test_cancel_during_key_probe_never_mutates_routes() {  Harness harness;
  harness.routes.cancel_during_fetch = true;
  const auto snap = harness.connect();
  expect(snap.code == TunnelCode::None, "canary cancel is not an egress failure");
  expect(snap.phase == TunnelPhase::Idle && snap.cleanup_verified, "canary cancel restores");
  expect(harness.routes.capture_calls == 0, "canary cancel installs no capture");
  expect(!harness.routes.pin_present && !harness.routes.canary_present, "canary cancel removes narrow routes");
  expect(harness.probe.calls == 0, "canary cancel does not open socks");
  expect(!harness.engine.running && !harness.files.config, "canary cancel removes process and config");
}

void test_cancel_before_and_after_pin() {
  Harness early;
  early.supervisor.set_hook([&](ConnectStep step) {
    if (step == ConnectStep::Resolved) early.cancel.request();
  });
  const auto before = early.connect();
  expect(before.phase == TunnelPhase::Idle && before.cleanup_verified, "cancel before pin restores");
  expect(before.code == TunnelCode::None, "cancel is not a server failure");
  expect(early.routes.add_calls == 0, "cancel before pin creates nothing");

  Harness late;
  late.supervisor.set_hook([&](ConnectStep step) {
    if (step == ConnectStep::Pinned) late.cancel.request();
  });
  const auto after = late.connect();
  expect(after.phase == TunnelPhase::Idle && after.cleanup_verified, "cancel after pin restores");
  expect(late.routes.add_calls == 1, "pin was created");
  expect(!late.routes.pin_present, "pin was removed");
  expect(!late.files.config, "config was removed");
}

void test_launch_failure_keeps_win32() {
  Harness harness;
  harness.engine.fail_launch = true;
  harness.engine.launch_error = 87;
  const auto snap = harness.connect();
  expect(snap.code == TunnelCode::CoreStartFailed, "launch failure code");
  expect(snap.message == "Сбой локальной службы туннеля", "launch failure text");
  int failed = -1;
  int idle = -1;
  for (int i = 0; i < static_cast<int>(harness.log.lines.size()); ++i) {
    const auto& line = harness.log.lines[static_cast<std::size_t>(i)];
    if (line.event == "core_create_process_failed" && line.win32 == 87) failed = i;
    if (line.event == "idle" && line.code == "core_start_failed") idle = i;
  }
  expect(failed >= 0 && idle > failed, "create-process win32 is logged before idle");
  expect(harness.routes.add_calls == 0, "launch failure adds no pin");
  expect(harness.engine.launch_calls == 1, "launch was attempted");
}

void test_job_assignment_is_mandatory() {
  Harness harness;
  harness.engine.job_ok = false;
  const auto snap = harness.connect();
  expect(snap.code == TunnelCode::CoreStartFailed, "job failure code");
  expect(snap.phase == TunnelPhase::Idle && snap.cleanup_verified, "job failure restores");
  expect(harness.engine.resume_calls == 0, "untracked process is not resumed");
  expect(harness.engine.kill_calls >= 1, "untracked process is killed");
  expect(!harness.engine.running, "process is gone");
  expect(!harness.routes.pin_present, "pin removed after job failure");
}

void test_tun_job_failure_restores_pin() {
  Harness harness;
  harness.routes.canary_ok = false;
  const auto snap = harness.connect();
  expect(snap.code == TunnelCode::RouteFailed, "canary failure code");
  expect(snap.message == "Сбой сетевого стека", "canary failure text");
  expect(snap.phase == TunnelPhase::Idle && snap.cleanup_verified, "canary failure restores");
  expect(harness.routes.add_calls == 1, "pin was created");
  expect(!harness.routes.pin_present, "pin was removed");
  expect(harness.routes.capture_calls == 0, "canary failure installs no capture");
  expect(harness.log.index_of("routes", "canary_failed") >= 0, "canary failure is logged");
}

void test_engine_death_and_probe_failure() {
  Harness dead;
  dead.routes.tun_misses = 100;
  const auto died = dead.connect();
  expect(died.code == TunnelCode::TunInitTimeout, "missing adapter times out");
  expect(died.message == "Сбой сетевого адаптера туннеля", "adapter text");
  expect(died.phase == TunnelPhase::Idle && died.cleanup_verified, "missing adapter restores");
  expect(dead.routes.capture_calls == 0 && dead.routes.add_calls == 0, "missing adapter adds no routes");
  expect(dead.log.index_of("tun_diag", "process_alive") >= 0, "timeout records a live process");
  expect(dead.log.index_of("tun_adapter", "none") >= 0, "timeout records an empty adapter list");
  expect(dead.log.index_of("tun_init_timeout", "adapter_not_found") >= 0, "missing name is not win32 0");
  int not_found = dead.log.index_of("tun_init_timeout", "adapter_not_found");
  expect(not_found >= 0 && dead.log.lines[static_cast<std::size_t>(not_found)].win32 == 0,
         "absent name keeps win32 0 because no create call failed");

  Harness probe;
  probe.routes.fetch_ok = false;
  const auto failed = probe.connect();
  expect(failed.code == TunnelCode::EgressTimeout, "canary timeout code");
  expect(failed.message == "Узел недоступен", "canary timeout text");
  expect(failed.phase == TunnelPhase::Idle && failed.cleanup_verified, "canary timeout restores");
  expect(probe.routes.capture_calls == 0, "canary timeout installs no capture");
  expect(!probe.routes.pin_present && !probe.routes.canary_present, "canary timeout removes narrow routes");
  expect(probe.supervisor.ledger_copy().routes.empty() && !probe.supervisor.ledger_copy().pin_intended,
         "ledger keeps neither pin nor canary");
  expect(probe.probe.calls == 0, "canary timeout does not use socks");

  Harness auth;
  auth.routes.fetch_ok = false;
  auth.engine.tail = "hysteria2: authentication failed \"password\":\"secret-password\"";
  const auto rejected = auth.connect();
  expect(rejected.code == TunnelCode::AuthRejected, "engine auth text is the key failure");
  expect(rejected.message == "Ключ не принят сервером", "auth text");
  expect(auth.routes.capture_calls == 0, "auth failure installs no capture");
  bool leaked = false;
  for (const auto& line : auth.log.lines) {
    if (line.code.find("secret-password") != std::string::npos) leaked = true;
  }
  expect(!leaked, "auth log drops the password");
}

void test_cleanup_failure_is_not_idle() {
  Harness harness;
  const auto connected = harness.connect();
  expect(connected.phase == TunnelPhase::Connected, "cleanup setup connected");
  harness.routes.delete_pin_failures = 1;
  const auto failed = harness.supervisor.disconnect(harness.cancel);
  expect(failed.phase == TunnelPhase::Disconnecting, "failed cleanup stays disconnecting");
  expect(failed.code == TunnelCode::CleanupFailed, "cleanup_failed");
  expect(!failed.cleanup_verified, "cleanup is not verified");
  expect(harness.supervisor.ledger_copy().pin_intended, "ledger keeps the pin");
  const BeginResult rejected = harness.supervisor.begin_connect();
  expect(!rejected.accepted && rejected.snap.code == TunnelCode::CleanupFailed, "connect waits for restore");
  const auto retried = harness.supervisor.disconnect(harness.cancel);
  expect(retried.phase == TunnelPhase::Idle && retried.cleanup_verified, "retry restores");
  expect(!harness.routes.pin_present, "retry removes the pin");
  expect(retried.generation == connected.generation, "generation survives restore");
}

void test_reconcile_dirty_ledger() {
  Harness harness;
  Ledger dirty;
  dirty.generation = 4;
  dirty.phase = TunnelPhase::Connected;
  dirty.pin_intended = true;
  dirty.pin.destination = "203.0.113.10";
  dirty.pin.interface_luid = 18;
  dirty.config_written = true;
  dirty.adapter_known = true;
  dirty.adapter.luid = 99;
  harness.files.stored = dirty;
  harness.files.has_ledger = true;
  harness.files.config = true;
  harness.routes.pin_present = true;
  harness.routes.adapter_present = true;
  harness.routes.routes_present = true;
  harness.engine.running = true;
  const auto snap = harness.supervisor.reconcile(harness.cancel);
  expect(snap.phase == TunnelPhase::Idle && snap.cleanup_verified, "reconcile restores");
  expect(!harness.routes.pin_present, "reconcile removes pin");
  expect(!harness.routes.adapter_present, "reconcile removes adapter");
  expect(!harness.files.config, "reconcile wipes config");
  expect(!harness.engine.running, "reconcile stops the engine");
  expect(encode_ledger(dirty).find("secret") == std::string::npos, "stored ledger has no secret field");
}

void test_watchdog() {
  Harness harness;
  expect(harness.connect().phase == TunnelPhase::Connected, "watchdog setup");
  expect(harness.supervisor.watchdog(harness.cancel).phase == TunnelPhase::Connected, "healthy watchdog");
  harness.engine.running = false;
  const auto lost = harness.supervisor.watchdog(harness.cancel);
  expect(lost.phase == TunnelPhase::Idle && lost.cleanup_verified, "dead process restores");
  expect(lost.message == "Соединение прервано", "link-lost text");
  expect(!harness.routes.pin_present, "watchdog removes the pin");

  Harness changed;
  expect(changed.connect().phase == TunnelPhase::Connected, "network setup");
  changed.routes.hardware_index = 99;
  const auto moved = changed.supervisor.watchdog(changed.cancel);
  expect(moved.phase == TunnelPhase::Idle && moved.cleanup_verified, "network change restores");
  expect(moved.message.find("Сеть изменилась") != std::string::npos, "network change text");
}

void test_idle_watchdog_ignores_stale_cancel() {
  Harness harness;
  expect(harness.connect().phase == TunnelPhase::Connected, "idle watchdog setup");
  expect(harness.supervisor.disconnect(harness.cancel).cleanup_verified, "restored");
  harness.cancel.request();
  const auto snap = harness.supervisor.watchdog(harness.cancel);
  expect(snap.phase == TunnelPhase::Idle && snap.cleanup_verified, "stale cancel stays idle");
  expect(harness.routes.add_calls == 1, "idle watchdog does not add routes");
}

void test_graceful_stop_skips_kill() {
  Harness harness;
  harness.engine.graceful = true;
  expect(harness.connect().phase == TunnelPhase::Connected, "graceful setup");
  const auto snap = harness.supervisor.disconnect(harness.cancel);
  expect(snap.cleanup_verified && snap.phase == TunnelPhase::Idle, "graceful restore");
  expect(harness.engine.kill_calls == 0, "graceful exit is not killed");
}

void test_ledger_roundtrip() {
  Ledger in;
  in.generation = 3;
  in.phase = TunnelPhase::Connecting;
  in.pid = 9;
  in.pin_intended = true;
  in.pin.destination = "203.0.113.10";
  in.pin.interface_luid = 7;
  in.pin.interface_index = 4;
  in.pin.physical_index = 4;
  in.pin.next_hop = "192.168.0.1";
  in.pin.metric = 25;
  in.adapter_known = true;
  in.adapter.name = "ProxyDomTun";
  in.adapter.guid = "{abc}";
  in.adapter.luid = 99;
  in.adapter.if_index = 5;
  OwnedRoute route;
  route.destination = "0.0.0.0";
  route.prefix_length = 1;
  route.interface_luid = 99;
  route.interface_index = 5;
  in.routes.push_back(route);
  in.config_written = true;
  const std::string text = encode_ledger(in);
  expect(text.find("password") == std::string::npos, "ledger vocabulary has no password");
  Ledger out;
  expect(decode_ledger(text, out), "decode");
  expect(out.generation == 3 && out.pin.destination == "203.0.113.10", "pin roundtrip");
  expect(out.routes.size() == 1 && out.routes[0].prefix_length == 1, "route roundtrip");
  expect(out.config_written && out.adapter.luid == 99, "adapter roundtrip");
  expect(!decode_ledger("nope", out), "reject a foreign ledger");
}

void test_user_proof_refusal_restores_capture() {
  Harness harness;
  harness.supervisor.accept_user_proof_for_tests(false);
  harness.supervisor.note_user_proof(false, 1);
  const auto snap = harness.connect();
  expect(snap.phase == TunnelPhase::Connected, "window proof does not block Connected");
  expect(harness.routes.capture_calls == 1, "capture is installed");
  expect(harness.routes.routes_present && harness.routes.pin_present, "capture and pin stay");
  expect(harness.supervisor.ledger_copy().routes.size() == 4, "ledger keeps four capture prefixes");
}

OwnedAdapter tun_row(bool up, std::uint64_t luid, unsigned long index) {
  OwnedAdapter adapter;
  adapter.name = "ProxyDomTun";
  adapter.guid = "{tun}";
  adapter.luid = luid;
  adapter.if_index = index;
  adapter.up = up;
  // A row Windows has finished checking. The tentative case is set explicitly
  // by the tests that care about it.
  adapter.dad_state = kIpDadStatePreferred;
  return adapter;
}

// A journal line matched by part. The diagnostic lines carry several fields, so
// an exact match would never find them.
int log_first_with(const FakeLog& log, const std::string& event, const std::string& part) {
  for (int i = 0; i < static_cast<int>(log.lines.size()); ++i) {
    const auto& line = log.lines[static_cast<std::size_t>(i)];
    if (line.event == event && line.code.find(part) != std::string::npos) return i;
  }
  return -1;
}

void test_classify_tun_wait() {
  TunWaitView dead;
  dead.process_alive = false;
  dead.process_exit = 3;
  const auto died = classify_tun_wait(dead);
  expect(std::string(died.code) == "process_died" && died.win32 == 3, "dead process is not a timeout");

  TunWaitView conflict;
  conflict.process_alive = true;
  conflict.list_ok = true;
  conflict.adapters = {tun_row(true, 9, 1), tun_row(false, 8, 2)};
  const auto names = classify_tun_wait(conflict);
  expect(std::string(names.code) == "adapter_name_conflict", "two names are a conflict");

  TunWaitView taken;
  taken.process_alive = true;
  taken.list_ok = true;
  taken.engine_text = "Cannot create a file when that file already exists";
  const auto text = classify_tun_wait(taken);
  expect(std::string(text.code) == "adapter_name_conflict", "already exists is a name conflict");

  TunWaitView down;
  down.process_alive = true;
  down.list_ok = true;
  down.adapters = {tun_row(false, 77, 3)};
  const auto state = classify_tun_wait(down);
  expect(std::string(state.code) == "adapter_state_not_up", "down adapter is not missing");

  TunWaitView created;
  created.process_alive = true;
  created.list_ok = true;
  created.engine_text = "configure tun interface win32=5";
  const auto win = classify_tun_wait(created);
  expect(std::string(win.code) == "wintun_create_failed" && win.win32 == 5, "stderr win32 is the create error");

  TunWaitView none;
  none.process_alive = true;
  none.list_ok = true;
  const auto missing = classify_tun_wait(none);
  expect(std::string(missing.code) == "adapter_not_found" && missing.win32 == 0, "empty list is not a win32");

  TunWaitView unread;
  unread.process_alive = true;
  unread.list_ok = false;
  unread.list_error = 122;
  const auto list = classify_tun_wait(unread);
  expect(std::string(list.code) == "adapter_not_found" && list.win32 == 122, "unreadable list keeps the api error");

  TunWaitView up;
  up.process_alive = true;
  up.list_ok = true;
  up.adapters = {tun_row(true, 99, 5)};
  const auto bare = classify_tun_wait(up);
  expect(std::string(bare.code) == "adapter_state_not_up",
         "an up adapter with no address is not usable yet");

  TunWaitView configured;
  configured.process_alive = true;
  configured.list_ok = true;
  OwnedAdapter addressed = tun_row(true, 99, 5);
  addressed.ipv4 = kTunIpv4;
  configured.adapters = {addressed};
  const auto ready = classify_tun_wait(configured);
  expect(std::string(ready.code) == "adapter_up", "a configured adapter is not adapter_not_found");
}

void test_tun_timeout_log_names_the_adapter() {
  Harness down;
  down.routes.tun_misses = 100;
  down.routes.use_listed = true;
  down.routes.listed = {tun_row(false, 77, 3)};
  const auto snap = down.connect();
  expect(snap.code == TunnelCode::TunInitTimeout, "down adapter still times out");
  expect(snap.message == "Сбой сетевого адаптера туннеля", "down adapter keeps the same caption");
  expect(snap.phase == TunnelPhase::Idle && snap.cleanup_verified, "down adapter still restores");
  expect(down.routes.add_calls == 0 && down.routes.capture_calls == 0, "diagnosis adds no routes");
  expect(down.log.index_of("tun_init_timeout", "adapter_state_not_up") >= 0, "down adapter is named");
  expect(log_first_with(down.log, "tun_adapter", "ProxyDomTun,up=0,luid=77,if=3") >= 0,
         "snapshot has luid");
  expect(log_first_with(down.log, "tun_adapter", "dad=4") >= 0,
         "snapshot carries the address state that decides readiness");

  Harness engine_text;
  engine_text.routes.tun_misses = 100;
  engine_text.engine.tail = "configure tun interface win32=5 \"password\":\"secret-password\"";
  const auto failed = engine_text.connect();
  expect(failed.code == TunnelCode::TunInitTimeout, "create text still times out");
  expect(failed.message == "Сбой сетевого адаптера туннеля", "create text keeps the caption");
  int create = -1;
  bool leaked = false;
  for (int i = 0; i < static_cast<int>(engine_text.log.lines.size()); ++i) {
    const auto& line = engine_text.log.lines[static_cast<std::size_t>(i)];
    if (line.event == "tun_init_timeout" && line.code == "wintun_create_failed" && line.win32 == 5) create = i;
    if (line.code.find("secret-password") != std::string::npos) leaked = true;
  }
  expect(create >= 0, "stderr win32 is logged");
  expect(!leaked, "engine text in the service log is redacted");
  bool kept = false;
  for (const auto& line : engine_text.log.lines) {
    if (line.event == "tun_stderr" &&
        line.code.find("configure tun interface win32=5 \"password\":\"***\"") != std::string::npos) {
      kept = true;
    }
  }
  expect(kept, "redacted stderr is kept");
}

void test_stderr_after_info_is_not_cut() {
  Harness harness;
  harness.routes.tun_misses = 100;
  std::string tail(300, 'I');
  tail += " win32=9 \"password\":\"secret-password\" end-of-engine";
  harness.engine.tail = tail;
  const auto snap = harness.connect();
  expect(snap.code == TunnelCode::TunInitTimeout, "late stderr still times out");
  expect(snap.message == "Сбой сетевого адаптера туннеля", "late stderr keeps the caption");
  expect(harness.routes.add_calls == 0, "late stderr adds no routes");
  expect(harness.log.index_of("tun_init_timeout", "wintun_create_failed") >= 0,
         "win32 after the info line is classified");
  std::string joined;
  bool leaked = false;
  int parts = 0;
  for (const auto& line : harness.log.lines) {
    if (line.code.find("secret-password") != std::string::npos) leaked = true;
    if (line.event != "tun_stderr") continue;
    ++parts;
    joined += line.code;
    joined.push_back('\n');
  }
  expect(parts >= 2, "stderr longer than one line is split");
  expect(joined.find("win32=9") != std::string::npos, "the error past 256 characters is logged");
  expect(joined.find("end-of-engine") != std::string::npos, "the tail of the engine text is logged");
  expect(joined.find("\"password\":\"***\"") != std::string::npos, "the secret is redacted in the chunks");
  expect(!leaked, "the password is not in the service log");
}

// The sanitizer is the only thing between an engine error and a journal file a
// non-admin user can read. Each shape below is one that reached the file at
// some point: a share line pasted into a log, a query-string secret, a
// credential key the key list did not know about, and a secret cut in half by
// the 4096-byte window.
void test_sanitizer_covers_every_credential_shape() {
  const std::string share =
      "dial hy2://alice:s3cr3t@cdn.example:443"
      "?obfs=salamander&obfs-password=obfsSecret&sni=cdn.example";
  const std::string masked = sanitize_engine_output_full(share);
  expect(masked.find("s3cr3t") == std::string::npos, "the userinfo password is masked");
  expect(masked.find("obfsSecret") == std::string::npos, "a query-string obfs password is masked");
  expect(masked.find("hy2://***@cdn.example") != std::string::npos, "the host survives userinfo masking");
  expect(masked.find("sni=cdn.example") != std::string::npos, "sni is not a credential");

  const std::string json =
      "{\"secret\":\"clashToken\",\"uuid\":\"11111111-2222-3333-4444-555555555555\","
      "\"user\":\"nodePassword\",\"public_key\":\"kept-visible\"}";
  const std::string json_masked = sanitize_engine_output_full(json);
  expect(json_masked.find("clashToken") == std::string::npos, "the clash secret is masked");
  expect(json_masked.find("11111111-2222") == std::string::npos, "the uuid is masked");
  expect(json_masked.find("nodePassword") == std::string::npos, "a bare username is masked");
  expect(json_masked.find("kept-visible") != std::string::npos,
         "the Reality public key stays readable");

  // The window cut used to run before redaction, so a secret that straddled
  // the boundary lost its `"password":"` prefix and survived whole.
  std::string wide(4000, 'x');
  wide += " \"password\":\"boundarySecret\"";
  const std::string wide_masked = sanitize_engine_output_full(wide);
  expect(wide_masked.find("boundarySecret") == std::string::npos,
         "a secret at the window edge is masked");
  expect(wide_masked.size() <= 4096, "the window bound still holds");

  // Idempotent: a masked line is masked again without turning *** into junk.
  expect(sanitize_engine_output_full(masked) == masked, "redaction is idempotent");

  const std::string kept = "event=egress code=timeout win32=1460 pid=1234";
  expect(sanitize_engine_output_full(kept) == kept,
         "ordinary fields are left alone");
}

// The leading cut kept the engine's opening banner and dropped the lines after
// it, which are the ones that name the fault. This pins the direction of the
// cut so a failure reason cannot hide behind a status line again.
void test_sanitizer_recent_keeps_the_failure_reason() {
  std::string banner = "event=core code=ok tun=ProxyDomTun";
  while (banner.size() < 300) banner += " routing_applied=true";
  const std::string text = banner + " tun rx=0 tx=0 hy2bind dial tcp 1.2.3.4:80";

  const std::string leading = sanitize_engine_output(text);
  const std::string recent = sanitize_engine_output_recent(text, 256);
  expect(leading.find("tun rx=0") == std::string::npos,
         "the leading cut still hides the reason");
  expect(recent.find("tun rx=0") != std::string::npos,
         "the recent cut keeps the line that names the fault");
  expect(recent.size() == 256, "the recent cut honours its bound");
  expect(recent == text.substr(text.size() - 256),
         "the recent cut is the tail of the text");

  const std::string brief = "event=egress code=probe_failed win32=10065";
  expect(sanitize_engine_output_recent(brief, 256) == brief,
         "text shorter than the bound is returned whole");
  expect(sanitize_engine_output_recent(brief, 0).size() == brief.size(),
         "a zero bound falls back to 256");

  const std::string secret = banner + " \"password\":\"tailSecret\"";
  expect(sanitize_engine_output_recent(secret, 256).find("tailSecret") == std::string::npos,
         "redaction runs before the recent cut too");
}

// The route lookup is a diagnostic. It runs before the probe and must never
// become a gate: a stack that cannot answer still gets the canary, because the
// probe's own error is what decides the session.
void test_route_lookup_is_diagnostic_only() {
  Harness answered;
  const auto connected = answered.connect();
  expect(connected.phase == TunnelPhase::Connected, "the lookup does not break a healthy connect");
  expect(answered.routes.lookup_calls == 1, "the route lookup runs once per attempt");
  const int lookup = log_first_with(answered.log, "route_lookup", "dest=");
  const int gate = log_first_with(answered.log, "gate", "egress");
  expect(lookup >= 0 && gate > lookup, "the lookup is recorded before the egress gate");
  expect(log_first_with(answered.log, "route_lookup", "idx=5") >= 0,
         "the journal names the interface the stack picked");

  Harness blind;
  blind.routes.lookup_ok = false;
  const auto still = blind.connect();
  expect(still.phase == TunnelPhase::Connected, "a failed lookup does not stop the tunnel");
  expect(blind.routes.fetch_calls == 1, "the canary still runs when the lookup cannot answer");
  expect(log_first_with(blind.log, "route_lookup", "none") >= 0, "a failed lookup is recorded as none");

  // Windows accepts a route row and can then lose it when the adapter's network
  // is re-identified. The stack stops picking our adapter, which is the only
  // visible sign, so the row goes back once and the probe runs afterwards.
  Harness moved;
  moved.routes.lookup_luid = 7;  // some other adapter, not ours
  const auto healed = moved.connect();
  expect(healed.phase == TunnelPhase::Connected, "a lost route is put back and the session connects");
  expect(moved.routes.canary_calls == 2, "the canary is re-asserted once");
  expect(log_first_with(moved.log, "routes", "canary_reasserted") >= 0,
         "the re-assert is recorded, so a silent drop stops being invisible");
  expect(log_first_with(moved.log, "gate", "egress") >= 0, "the probe still runs after the repair");
}

// The probe resolve used to end the session without a word from the engine, so
// a lookup that never entered the tun and one that entered and went nowhere
// looked identical. The counters name which, and dst= names where they went.
void test_probe_resolve_failure_shows_the_engine_counters() {
  Harness h;
  h.names.fail_on_call = 2;
  h.engine.tail = "tun rx=4 tx=0 dst=198.18.0.2";
  const auto snap = h.connect();
  expect(snap.code == TunnelCode::ResolveFailed, "the probe resolve is the one that failed");
  expect(log_first_with(h.log, "core_output", "tun rx=4") >= 0,
         "a failed lookup still shows what the engine counted");
  expect(log_first_with(h.log, "core_output", "dst=198.18.0.2") >= 0,
         "the counters name where the packets were addressed");
}

// The fix itself. Windows publishes the address before it can carry traffic, so
// a session that probes the moment the address appears fails on every node with
// egress_timeout. Here the address stays tentative for 1.5 s and the session has
// to wait it out and then connect.
void test_connect_waits_for_a_preferred_address() {
  Harness slow;
  slow.routes.tentative_polls = 15;
  const auto connected = slow.connect();
  expect(connected.phase == TunnelPhase::Connected, "a slow address still connects");
  expect(slow.routes.fetch_calls == 1, "the probe runs once, after the wait");

  const int waited = log_first_with(slow.log, "tun_wait_ms", "1500");
  expect(waited >= 0, "the wait is recorded, so it stops being invisible");
  expect(log_first_with(slow.log, "adapter", kTunIpv4) > waited,
         "the adapter is only accepted after the wait");
  expect(log_first_with(slow.log, "tun_init_timeout", "adapter_") < 0,
         "a slow address is not a timeout");
}

void test_resolve_and_route_table_failures() {
  Harness names;
  names.names.fail = true;
  const auto unresolved = names.connect();
  expect(unresolved.code == TunnelCode::ResolveFailed && unresolved.cleanup_verified, "resolve failure restores");
  expect(names.routes.add_calls == 0, "resolve failure adds no pin");

  Harness table;
  table.routes.defaults_ok = false;
  const auto unread = table.connect();
  expect(unread.code == TunnelCode::RouteFailed && unread.cleanup_verified, "unreadable table does not connect");
  expect(table.routes.add_calls == 0, "unreadable table adds no pin");
}

}  // namespace

// The counters are the only thing in the journal that can say whether a game's
// UDP left the tunnel or was carried inside the proxy stream. Without them the
// owner is guessing from packet loss alone.
void test_flow_counters_record_the_outbound() {
  Harness h;
  auto state = std::make_shared<FlowState>();
  state->rows = {
      flow_row("d-1", "udp", "direct", "10.20.30.40:27015", 900 * 1024, 4 * 1024 * 1024),
      flow_row("p-1", "udp", "proxy", "142.250.1.1:443", 200 * 1024, 300 * 1024),
      flow_row("t-1", "tcp", "proxy", "104.16.0.1:443", 2048, 2048),
  };
  unsigned short seen_port = 0;
  std::string seen_secret;
  h.supervisor.set_flow_factory(
      [&state, &seen_port, &seen_secret](unsigned short port,
                                         const std::string& secret) -> std::unique_ptr<FlowProbe> {
        seen_port = port;
        seen_secret = secret;
        return std::unique_ptr<FlowProbe>(new FakeFlows(state));
      });

  const auto connected = h.connect();
  expect(connected.phase == TunnelPhase::Connected, "flow session connects");
  expect(seen_port == 17890, "the controller port comes from the free-port pick");
  expect(seen_secret.size() == 48, "the controller carries a per-session secret");
  expect(h.files.config_body.find("\"api_port\":17890") != std::string::npos,
         "the engine config records the controller port");
  expect(h.files.config_body.find(seen_secret) != std::string::npos,
         "the engine config records the controller secret");

  h.supervisor.watchdog(h.cancel);
  const bool announced_direct =
      std::any_of(h.log.lines.begin(), h.log.lines.end(), [](const FakeLog::Line& line) {
        return line.event == "flow_seen" && line.code.find("chain=direct") != std::string::npos &&
               line.code.find("dst=10.20.30.40:27015") != std::string::npos;
      });
  const bool announced_proxy =
      std::any_of(h.log.lines.begin(), h.log.lines.end(), [](const FakeLog::Line& line) {
        return line.event == "flow_seen" && line.code.find("chain=proxy") != std::string::npos;
      });
  expect(announced_direct, "a direct udp flow is announced with its destination");
  expect(announced_proxy, "a proxied udp flow is announced too, so the two are comparable");

  h.supervisor.disconnect(h.cancel);
  const bool totals =
      std::any_of(h.log.lines.begin(), h.log.lines.end(), [](const FakeLog::Line& line) {
        return line.event == "flow_total" && line.code.find("udp:direct=dn:") != std::string::npos &&
               line.code.find("udp:proxy=dn:") != std::string::npos;
      });
  expect(totals, "the closing line carries a total per network and outbound");

  // A controller that answers nothing must not cost the session or spam the log.
  Harness blind;
  auto dead = std::make_shared<FlowState>();
  dead->reachable = false;
  blind.supervisor.set_flow_factory([dead](unsigned short, const std::string&) {
    return std::unique_ptr<FlowProbe>(new FakeFlows(dead));
  });
  const auto still_up = blind.connect();
  for (int tick = 0; tick < 3; ++tick) blind.supervisor.watchdog(blind.cancel);
  blind.supervisor.disconnect(blind.cancel);
  expect(still_up.phase == TunnelPhase::Connected, "an unreadable controller does not fail connect");
  int complaints = 0;
  for (const auto& line : blind.log.lines) {
    if (line.event == "flow" && line.code == "api_unreachable") ++complaints;
  }
  expect(complaints == 1, "an unreachable controller is reported once, not every tick");
}

void test_connections_body_parses() {
  const std::string body =
      R"({"downloadTotal":9,"uploadTotal":3,"connections":[)"
      R"({"id":"a","metadata":{"network":"udp","type":"","sourceIP":"198.18.0.1",)"
      R"("destinationIP":"10.20.30.40","destinationPort":"27015","host":"",)"
      R"("processPath":"C:\\Games\\dota 2\\bin\\dota2.exe"},"upload":120,"download":4096,)"
      R"("start":"2026-10-03T10:00:00Z","chains":["tun-in","direct"],"rule":"udp-bypass"},)"
      R"({"id":"b","metadata":{"network":"tcp","destinationIP":"1.1.1.1","destinationPort":"443"},)"
      R"("upload":10,"download":20,"chains":["proxy"],"rule":"final"}]})";
  std::vector<FlowRow> rows;
  expect(parse_connections(body, rows), "the clash api body parses");
  expect(rows.size() == 2, "both connections are read");
  if (rows.size() != 2) return;
  expect(rows[0].network == "udp" && rows[0].chain == "direct", "network and last hop are taken");
  expect(rows[0].destination == "10.20.30.40:27015", "a destination is ip plus port");
  expect(rows[0].process == "dota2.exe", "the owning process is named by its leaf");
  expect(rows[0].upload == 120 && rows[0].download == 4096, "byte counts survive");
  expect(rows[0].id == "a" && rows[1].id == "b", "the connection id is read");
  expect(rows[1].chain == "proxy", "the other hop is not mistaken");

  // A member the engine has never heard of must not cost us the counts.
  const std::string future =
      R"({"connections":[{"id":"c","metadata":{"network":"udp","destinationIP":"1.2.3.4",)"
      R"("destinationPort":"5","somethingNew":{"nested":[1,2,3]}},"upload":1,"download":2,)"
      R"("brandNew":true,"chains":["direct"]}],"extra":42})";
  expect(parse_connections(future, rows), "an unknown field does not fail the parse");
  expect(rows.size() == 1, "the row still arrives");
  expect(!rows.empty() && rows[0].download == 2 && rows[0].chain == "direct",
         "the counts still come through");

  // Without an id the row cannot be told apart from next poll's row, so it must
  // not reach the total: banking it would count the same bytes every poll.
  const std::string anonymous =
      R"({"connections":[{"metadata":{"network":"udp","destinationIP":"1.2.3.4",)"
      R"("destinationPort":"5"},"upload":9,"download":99,"chains":["direct"]}]})";
  std::size_t untracked = 0;
  expect(parse_connections(anonymous, rows, &untracked), "the body itself still parses");
  expect(rows.empty(), "a connection with no id is left out of the sample");
  expect(untracked == 1, "and is counted so the session can say so once");

  expect(!parse_connections("", rows), "an empty body is not a sample");
  expect(!parse_connections("{\"downloadTotal\":1}", rows), "a body without connections is refused");
}

// The clash api reports each connection's own cumulative counters. Adding them
// to the total on every poll counts each connection's whole history once per
// poll, which is what made a still lobby report gigabytes. The total has to be
// the sum of per-id deltas, and it must never go backwards.
void test_connection_ids_make_the_total_monotonic() {
  Harness h;
  auto state = std::make_shared<FlowState>();
  // One game flow that keeps moving, and later a replacement for it.
  state->script = {
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 1000, 100000)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 1100, 300000)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 1200, 900000)},
      // "game" is gone. A new id starts from wherever it starts; none of the
      // old flow's bytes are re-counted.
      {flow_row("game2", "udp", "direct", "162.254.9.9:27015", 50, 700)},
      {flow_row("game2", "udp", "direct", "162.254.9.9:27015", 150, 2700)},
  };
  std::uint64_t now = 0;
  h.supervisor.set_clock([&now] { return now; });
  h.supervisor.set_flow_factory([state](unsigned short, const std::string&) {
    return std::unique_ptr<FlowProbe>(new FakeFlows(state));
  });

  const auto connected = h.connect();
  expect(connected.phase == TunnelPhase::Connected, "the session connects");

  for (int step = 0; step < 5; ++step) {
    now += 5000;
    h.supervisor.watchdog(h.cancel);
  }
  h.supervisor.disconnect(h.cancel);

  // Read every total the journal printed and prove none of them went backwards.
  std::uint64_t last_down = 0;
  bool monotonic = true;
  std::uint64_t printed = 0;
  for (const auto& line : h.log.lines) {
    if (line.event != "flow_summary" && line.event != "flow_total") continue;
    const std::string marker = "udp:direct=dn:";
    const auto at = line.code.find(marker);
    if (at == std::string::npos) continue;
    const std::uint64_t value = std::stoull(line.code.substr(at + marker.size()));
    if (value < last_down) monotonic = false;
    last_down = value;
    printed = static_cast<std::uint64_t>(std::count(line.code.begin(), line.code.end(), '='));
  }
  expect(monotonic, "a session total never goes backwards");
  // 200000 on the second poll, 600000 on the third, 2000 after the flow was
  // replaced. Adding the raw counters instead would report 1704200, because
  // every poll would re-count the history of whatever was still connected.
  expect(last_down == 802000, "the total is the sum of per-id deltas, not of raw counters");
  expect(printed > 0, "the closing line carries a total per network and outbound");
}

// A dip is a lull in a window, so it is measured rather than left for the reader
// to reconstruct from two totals.
void test_a_lull_is_journalled_as_a_number() {
  Harness h;
  auto state = std::make_shared<FlowState>();
  // Poll 1 establishes the baseline. Polls 2-3 move nothing, which is ten seconds
  // of stillness and closes the first window. Poll 4 moves again, which ends it.
  state->script = {
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 1000, 100000)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 1000, 100000)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 1000, 100000)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 2000, 200000)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 3000, 300000)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 4000, 400000)},
  };
  std::uint64_t now = 0;
  h.supervisor.set_clock([&now] { return now; });
  h.supervisor.set_flow_factory([state](unsigned short, const std::string&) {
    return std::unique_ptr<FlowProbe>(new FakeFlows(state));
  });

  h.connect();
  for (int step = 0; step < 6; ++step) {
    now += 5000;
    h.supervisor.watchdog(h.cancel);
  }

  std::vector<std::string> rates;
  for (const auto& line : h.log.lines) {
    if (line.event == "flow_rate") rates.push_back(line.code);
  }
  expect(rates.size() == 2, "one rate line per summary window");

  if (rates.size() == 2) {
    // Window one closed while the lull was still running, so it has no completed
    // stall yet and says so with a running figure instead of a zero that would
    // read as "nothing happened".
    expect(rates[0].find("quiet_ms=10000") != std::string::npos,
           "the lull in progress is journalled");
    expect(rates[0].find("stall_ms:0 stalls:0") != std::string::npos,
           "a lull that has not ended yet is not counted as a completed one");
    expect(rates[0].find("udp:direct=dn_kbps:0") != std::string::npos,
           "a window with no bytes reads zero rather than nothing");
    // Window two is where the lull ended, so it is this window's stall.
    expect(rates[1].find("stall_ms:10000 stalls:1") != std::string::npos,
           "the longest lull of the window is journalled, and how many there were");
    expect(rates[1].find("quiet_ms:0") != std::string::npos,
           "traffic resuming clears the lull in progress");
    expect(rates[1].find("live:1") != std::string::npos,
           "the number of live udp connections is journalled, so a re-established "
           "flow is distinguishable from a stall");
    expect(rates[1].find("udp:direct=dn_kbps:19") != std::string::npos,
           "the rate is measured over the window, not inferred from totals");
  }
}

// The flaw this replaces: worst_quiet_ms was a record for the whole session. It
// was set during the first lull and could never move again without exceeding
// it, so in a real session it froze while four later stalls went past unseen.
void test_a_later_dip_is_not_hidden_by_the_session_record() {
  Harness h;
  auto state = std::make_shared<FlowState>();
  // A twenty-second stall, then a ten-second one. Both are real dips; the second
  // is smaller, and a record could not show it. Ten-second steps put two polls
  // in each summary window.
  state->script = {
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 1000, 100000)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 1000, 100000)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 1000, 100000)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 2000, 200000)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 2000, 200000)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 3000, 300000)},
  };
  std::uint64_t now = 0;
  h.supervisor.set_clock([&now] { return now; });
  h.supervisor.set_flow_factory([state](unsigned short, const std::string&) {
    return std::unique_ptr<FlowProbe>(new FakeFlows(state));
  });

  h.connect();
  for (int step = 0; step < 6; ++step) {
    now += 10000;
    h.supervisor.watchdog(h.cancel);
  }

  std::vector<std::string> rates;
  for (const auto& line : h.log.lines) {
    if (line.event == "flow_rate") rates.push_back(line.code);
  }
  expect(rates.size() == 3, "three windows at ten-second steps");

  if (rates.size() == 3) {
    expect(rates[1].find("stall_ms:20000 stalls:1") != std::string::npos,
           "the first stall is reported in the window it ended in");
    expect(rates[2].find("stall_ms:10000 stalls:1") != std::string::npos,
           "the later, smaller dip is still reported, even though the record is larger");
    expect(rates[2].find("worst_quiet_ms=20000") != std::string::npos,
           "the session record is still carried, as history");
  }
}

// Two chains, one quiet. "Nothing moved anywhere" is not the question; whether
// the chain carrying the game went quiet while another kept dripping is.
void test_silence_is_counted_per_chain() {
  Harness h;
  auto state = std::make_shared<FlowState>();
  // The tunnel chain dribbles on every poll. The game chain is still from the
  // second poll to the fourth, so a single global counter would be reset by the
  // tunnel on every sample and would report a healthy network.
  state->script = {
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 1000, 100000),
       flow_row("web", "tcp", "proxy", "142.250.1.1:443", 1000, 100000)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 1000, 100000),
       flow_row("web", "tcp", "proxy", "142.250.1.1:443", 2000, 200200)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 1000, 100000),
       flow_row("web", "tcp", "proxy", "142.250.1.1:443", 3000, 300300)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 2000, 200000),
       flow_row("web", "tcp", "proxy", "142.250.1.1:443", 4000, 400400)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 3000, 300000),
       flow_row("web", "tcp", "proxy", "142.250.1.1:443", 5000, 500500)},
      {flow_row("game", "udp", "direct", "162.254.1.1:27015", 4000, 400000),
       flow_row("web", "tcp", "proxy", "142.250.1.1:443", 6000, 600600)},
  };
  std::uint64_t now = 0;
  h.supervisor.set_clock([&now] { return now; });
  h.supervisor.set_flow_factory([state](unsigned short, const std::string&) {
    return std::unique_ptr<FlowProbe>(new FakeFlows(state));
  });

  h.connect();
  for (int step = 0; step < 6; ++step) {
    now += 5000;
    h.supervisor.watchdog(h.cancel);
  }

  std::vector<std::string> rates;
  for (const auto& line : h.log.lines) {
    if (line.event == "flow_rate") rates.push_back(line.code);
  }
  expect(rates.size() == 2, "one rate line per summary window");

  if (rates.size() == 2) {
    expect(rates[1].find("udp:direct=dn_kbps:19/up_kbps:0 stall_ms:10000 stalls:1") !=
               std::string::npos,
           "the game chain is shown stalled while the tunnel keeps carrying the window");
    expect(rates[1].find("tcp:proxy=dn_kbps:") != std::string::npos &&
               rates[1].find("tcp:proxy=") != std::string::npos &&
               rates[1].find("stall_ms:0 stalls:0 quiet_ms:0 live:") != std::string::npos,
           "the tunnel chain is reported on its own terms, and is not stalled");
  }
}

// Counters the session cannot attribute must say so, once, rather than read as
// a quiet network.
void test_an_unattributable_row_is_reported_once() {
  Harness h;
  auto state = std::make_shared<FlowState>();
  state->script = {
      {FlowRow()},  // no id: the engine reported something we cannot track
      {FlowRow()},
      {FlowRow()},
      {FlowRow()},
  };
  state->untracked = 1;
  std::uint64_t now = 0;
  h.supervisor.set_clock([&now] { return now; });
  h.supervisor.set_flow_factory([state](unsigned short, const std::string&) {
    return std::unique_ptr<FlowProbe>(new FakeFlows(state));
  });

  h.connect();
  for (int step = 0; step < 4; ++step) {
    now += 5000;
    h.supervisor.watchdog(h.cancel);
  }

  int complaints = 0;
  for (const auto& line : h.log.lines) {
    if (line.event == "flow" && line.code == "no_connection_id") ++complaints;
  }
  expect(complaints == 1, "an unattributable connection is reported once, not every poll");
  bool any_total = false;
  for (const auto& line : h.log.lines) {
    if (line.event == "flow_summary") any_total = true;
  }
  expect(!any_total, "and no total is invented from bytes that cannot be attributed");
}

// ADR 034. The pipe is a channel, not a lease. Only a lost client is allowed
// to leave the tunnel up; every other reason must still stop it, so a later
// edit cannot quietly turn another teardown path into a keep-alive.
void test_only_a_lost_client_keeps_the_tunnel() {
  expect(!tunnel_should_stop(TeardownReason::ClientGone),
         "a closed pipe is not a stop request");
  expect(tunnel_should_stop(TeardownReason::Explicit), "the user can still stop the tunnel");
  expect(tunnel_should_stop(TeardownReason::ServiceStop), "a service stop tears the tunnel down");
  expect(tunnel_should_stop(TeardownReason::Suspend), "sleep tears the tunnel down");
  expect(tunnel_should_stop(TeardownReason::Lost), "a lost engine tears the tunnel down");
  expect(std::string(reason_name(TeardownReason::ClientGone)) == "client_gone",
         "the journal names the reason");
  expect(std::string(reason_name(TeardownReason::Suspend)) == "suspend",
         "every reason has a name");
}

// The engine opens the wintun adapter first and assigns the address with a
// separate netsh process afterwards, and Windows reports an address-less
// adapter as up. Readiness that accepted "up" alone let the egress probe run
// against an adapter with no address: the connect failed in about a
// millisecond and the journal blamed the node.
void test_tun_readiness_needs_the_address() {
  OwnedAdapter bare = tun_row(true, 99, 5);
  expect(!tun_adapter_ready(bare), "an adapter with no address is not ready");

  OwnedAdapter ready = tun_row(true, 99, 5);
  ready.ipv4 = kTunIpv4;
  expect(tun_adapter_ready(ready), "the configured adapter is ready");

  OwnedAdapter other = tun_row(true, 99, 5);
  other.ipv4 = "169.254.1.1";
  expect(!tun_adapter_ready(other), "another address is not our adapter");

  OwnedAdapter down = tun_row(false, 99, 5);
  down.ipv4 = kTunIpv4;
  expect(!tun_adapter_ready(down), "a down adapter is not ready");

  OwnedAdapter legacy = tun_row(true, 99, 5);
  legacy.name = "teremokhy2";
  legacy.ipv4 = kTunIpv4;
  expect(!tun_adapter_ready(legacy), "the legacy name is cleaned up, never routed");

  OwnedAdapter no_luid = tun_row(true, 0, 5);
  no_luid.ipv4 = kTunIpv4;
  expect(!tun_adapter_ready(no_luid), "a zero luid cannot carry a route");

  OwnedAdapter no_index = tun_row(true, 99, 0);
  no_index.ipv4 = kTunIpv4;
  expect(!tun_adapter_ready(no_index), "a zero index cannot carry a route");
}

// The owner's machine settled this one: adapter_state reported media=1 dad=1
// and route_lookup came back ERROR_NOT_FOUND for a canary whose /32 row was in
// the table. The address was present and Windows was still checking it for a
// duplicate, so the stack had no usable source and refused the route. An
// address is not ready until it is Preferred.
void test_tun_readiness_needs_a_preferred_address() {
  OwnedAdapter tentative = tun_row(true, 99, 5);
  tentative.ipv4 = kTunIpv4;
  tentative.dad_state = kIpDadStateTentative;
  expect(!tun_adapter_ready(tentative), "a tentative address is not ready");

  OwnedAdapter duplicate = tun_row(true, 99, 5);
  duplicate.ipv4 = kTunIpv4;
  duplicate.dad_state = 2;
  expect(!tun_adapter_ready(duplicate), "a duplicate address is not ready");

  OwnedAdapter deprecated = tun_row(true, 99, 5);
  deprecated.ipv4 = kTunIpv4;
  deprecated.dad_state = 3;
  expect(!tun_adapter_ready(deprecated), "a deprecated address is not ready");

  OwnedAdapter preferred = tun_row(true, 99, 5);
  preferred.ipv4 = kTunIpv4;
  preferred.dad_state = kIpDadStatePreferred;
  expect(tun_adapter_ready(preferred), "a preferred address is ready");

  // The timeout diagnosis has to name this state rather than call it "down",
  // because "wait longer" and "the adapter never came up" need different fixes.
  TunWaitView view;
  view.process_alive = true;
  view.list_ok = true;
  view.adapters = {tentative};
  expect(classify_tun_wait(view).code == std::string("adapter_address_tentative"),
         "a tentative address is named on its own");
  expect(classify_tun_wait(view).win32 == kIpDadStateTentative,
         "the diagnosis carries the dad state it saw");
}

int main() {
  test_route_policy();
  test_slash_port_connects_and_junk_does_not_launch();
  test_foreign_blocks_before_pin();
  test_radmin_allows_connect();
  test_bad_key_never_mutates_routes();
  test_a_refused_transport_is_not_a_crash();
  test_a_refused_security_keeps_its_own_name();
  test_an_unknown_word_is_still_a_core_exit();
  test_cancel_during_key_probe_never_mutates_routes();
  test_cancel_before_and_after_pin();
  test_launch_failure_keeps_win32();
  test_job_assignment_is_mandatory();
  test_tun_job_failure_restores_pin();
  test_engine_death_and_probe_failure();
  test_cleanup_failure_is_not_idle();
  test_reconcile_dirty_ledger();
  test_watchdog();
  test_idle_watchdog_ignores_stale_cancel();
  test_graceful_stop_skips_kill();
  test_ledger_roundtrip();
  test_user_proof_refusal_restores_capture();
  test_classify_tun_wait();
  test_tun_readiness_needs_the_address();
  test_tun_readiness_needs_a_preferred_address();
  test_tun_timeout_log_names_the_adapter();
  test_stderr_after_info_is_not_cut();
  test_sanitizer_covers_every_credential_shape();
  test_sanitizer_recent_keeps_the_failure_reason();
  test_route_lookup_is_diagnostic_only();
  test_probe_resolve_failure_shows_the_engine_counters();
  test_connect_waits_for_a_preferred_address();
  test_resolve_and_route_table_failures();
  test_flow_counters_record_the_outbound();
  test_connections_body_parses();
  test_connection_ids_make_the_total_monotonic();
  test_a_lull_is_journalled_as_a_number();
  test_a_later_dip_is_not_hidden_by_the_session_record();
  test_silence_is_counted_per_chain();
  test_an_unattributable_row_is_reported_once();
  test_only_a_lost_client_keeps_the_tunnel();
  if (g_failed != 0) {
    std::cerr << g_failed << " failed\n";
    return 1;
  }
  std::cout << "ok\n";
  return 0;
}
