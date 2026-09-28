#include "session_supervisor.h"

#include <iostream>
#include <string>

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
  bool pin_present = false;
  int add_calls = 0;
  int delete_pin_failures = 0;
  bool adapter_present = false;
  bool routes_present = false;
  bool remove_ok = true;
  bool delete_routes_ok = true;
  int tun_misses = 0;
  bool prove_ok = true;
  int prove_calls = 0;
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
    return true;
  }
  bool routes_absent(std::uint64_t) override { return !routes_present; }
  bool list_own_adapters(std::vector<OwnedAdapter>& out) override {
    out.clear();
    if (!list_ok) return false;
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
  bool tun_ready(OwnedAdapter& adapter, std::vector<OwnedRoute>& halves) override {
    if (tun_misses > 0) {
      --tun_misses;
      return false;
    }
    adapter_present = true;
    routes_present = true;
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
  bool graceful = false;
  bool unkillable = false;
  int kill_calls = 0;
  int resume_calls = 0;
  int assign_calls = 0;
  int launch_calls = 0;

  bool launch_suspended(unsigned long& pid) override {
    ++launch_calls;
    running = true;
    pid = 42;
    return true;
  }
  bool assign_job() override {
    ++assign_calls;
    return job_ok;
  }
  bool resume() override {
    ++resume_calls;
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
  unsigned long last_error() const override { return 0; }
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
  void write(std::int64_t, const std::string&, const std::string&, unsigned long) override {}
};

class FakeSleep : public Sleeper {
 public:
  void sleep_ms(int) override {}
};

struct Harness {
  FakeRoutes routes;
  FakeEngine engine;
  FakeNames names;
  FakeFiles files;
  FakeLog log;
  FakeSleep sleeper;
  TunnelSupervisor supervisor;
  CancelFlag cancel;

  Harness() : supervisor(routes, engine, names, files, log, sleeper) { routes.cancel = &cancel; }

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

void test_foreign_blocks_before_pin() {
  Harness harness;
  harness.routes.defaults = {route_view("happ-xray", false, 0, 0), route_view("Ethernet", true, 0, 25)};
  const auto snap = harness.connect();
  expect(snap.phase == TunnelPhase::Idle, "foreign ends idle");
  expect(snap.code == TunnelCode::ForeignTunnel, "foreign code");
  expect(snap.cleanup_verified, "foreign did not need cleanup");
  expect(snap.message.find("happ-xray") != std::string::npos, "foreign names the adapter");
  expect(harness.routes.add_calls == 0, "foreign adds no pin");
  expect(!harness.files.config, "foreign writes no config");
}

void test_radmin_allows_connect() {
  Harness harness;
  harness.routes.defaults = {route_view("Radmin VPN", false, 0, 9256), route_view("Ethernet", true, 0, 25)};
  const auto snap = harness.connect();
  expect(snap.phase == TunnelPhase::Connected, "radmin does not block");
  expect(snap.cleanup_verified == false, "connected is not a restore");
  expect(harness.files.config_body.find("secret-password") != std::string::npos, "engine config keeps the secret");
  expect(encode_ledger(harness.supervisor.ledger_copy()).find("secret-password") == std::string::npos,
         "ledger has no password");
  expect(encode_ledger(harness.supervisor.ledger_copy()).find("hide") == std::string::npos, "ledger has no obfs secret");
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

void test_engine_death_and_probe_failure() {
  Harness dead;
  dead.engine.unkillable = false;
  dead.routes.tun_misses = 100;
  const auto died = dead.connect();
  expect(died.code == TunnelCode::TunNotReady, "dead engine is tun_not_ready");
  expect(died.phase == TunnelPhase::Idle && died.cleanup_verified, "dead engine restores");

  Harness probe;
  probe.routes.prove_ok = false;
  const auto failed = probe.connect();
  expect(failed.code == TunnelCode::EgressFailed, "probe failure stays egress_failed");
  expect(failed.phase == TunnelPhase::Idle && failed.cleanup_verified, "probe failure still restores");
  expect(failed.message.find("Сервер не отвечает") != std::string::npos, "egress text");
  expect(!probe.routes.pin_present && !probe.files.config, "probe failure leaves no owned resources");
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
  test_foreign_blocks_before_pin();
  test_radmin_allows_connect();
  test_cancel_before_and_after_pin();
  test_job_assignment_is_mandatory();
  test_engine_death_and_probe_failure();
  test_cleanup_failure_is_not_idle();
  test_reconcile_dirty_ledger();
  test_watchdog();
  test_graceful_stop_skips_kill();
  test_ledger_roundtrip();
  test_resolve_and_route_table_failures();
  if (g_failed != 0) {
    std::cerr << g_failed << " failed\n";
    return 1;
  }
  std::cout << "ok\n";
  return 0;
}
