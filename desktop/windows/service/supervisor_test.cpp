#include "session_supervisor.h"

#include <iostream>
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
    adapter_present = true;
    adapter.name = "ProxyDomTun";
    adapter.guid = "{tun}";
    adapter.luid = 99;
    adapter.if_index = 5;
    adapter.up = true;
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
  bool resolve_ipv4(const std::string& host, std::string& ip) override {
    if (fail) return false;
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

void test_cancel_during_key_probe_never_mutates_routes() {
  Harness harness;
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
  return adapter;
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
  const auto ready = classify_tun_wait(up);
  expect(std::string(ready.code) == "adapter_up", "an up adapter is not adapter_not_found");
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
  expect(down.log.index_of("tun_adapter", "ProxyDomTun,up=0,luid=77,if=3") >= 0, "snapshot has luid");

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

int main() {
  test_route_policy();
  test_slash_port_connects_and_junk_does_not_launch();
  test_foreign_blocks_before_pin();
  test_radmin_allows_connect();
  test_bad_key_never_mutates_routes();
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
  test_tun_timeout_log_names_the_adapter();
  test_stderr_after_info_is_not_cut();
  test_resolve_and_route_table_failures();
  if (g_failed != 0) {
    std::cerr << g_failed << " failed\n";
    return 1;
  }
  std::cout << "ok\n";
  return 0;
}
