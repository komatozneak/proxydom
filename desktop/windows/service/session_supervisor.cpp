#include "session_supervisor.h"

#include "protocol.h"

#include <algorithm>
#include <map>
#include <sstream>

namespace {

const char* kLost = "Соединение прервано";
const char* kChanged = "Сеть изменилась. Подключение остановлено.";

std::string field(const std::string& text, const std::string& key) {
  const std::string prefix = key + "=";
  std::size_t at = 0;
  while (at < text.size()) {
    auto end = text.find('\n', at);
    if (end == std::string::npos) end = text.size();
    const std::string line = text.substr(at, end - at);
    if (line.compare(0, prefix.size(), prefix) == 0) return line.substr(prefix.size());
    at = end + 1;
  }
  return {};
}

bool truth(const std::string& text) { return text == "1"; }

unsigned long number_field(const std::string& text, const std::string& key) {
  const std::string value = field(text, key);
  if (value.empty()) return 0;
  try {
    return static_cast<unsigned long>(std::stoul(value));
  } catch (...) {
    return 0;
  }
}

TunnelPhase phase_from(const std::string& text) {
  if (text == "connecting") return TunnelPhase::Connecting;
  if (text == "connected") return TunnelPhase::Connected;
  if (text == "disconnecting") return TunnelPhase::Disconnecting;
  return TunnelPhase::Idle;
}

std::string scrub(std::string text) {
  for (char& c : text) {
    if (c == '\n' || c == '\r' || c == '=') c = ' ';
  }
  return text;
}

}  // namespace

const char* phase_name(TunnelPhase phase) {
  switch (phase) {
    case TunnelPhase::Connecting:
      return "connecting";
    case TunnelPhase::Connected:
      return "connected";
    case TunnelPhase::Disconnecting:
      return "disconnecting";
    case TunnelPhase::Idle:
      return "idle";
  }
  return "idle";
}

const char* code_name(TunnelCode code) {
  switch (code) {
    case TunnelCode::ResolveFailed:
      return "resolve_failed";
    case TunnelCode::ForeignTunnel:
      return "foreign_tunnel";
    case TunnelCode::RouteFailed:
      return "route_failed";
    case TunnelCode::CoreStartFailed:
      return "core_start_failed";
    case TunnelCode::KeyProbeFailed:
      return "key_probe_failed";
    case TunnelCode::TunNotReady:
      return "tun_not_ready";
    case TunnelCode::EgressFailed:
      return "egress_failed";
    case TunnelCode::CleanupFailed:
      return "cleanup_failed";
    case TunnelCode::Busy:
      return "busy";
    case TunnelCode::Protocol:
      return "protocol";
    case TunnelCode::None:
      return "";
  }
  return "";
}

std::string user_message(TunnelCode code, const std::string& extra) {
  switch (code) {
    case TunnelCode::ResolveFailed:
      return "Не удалось определить адрес сервера";
    case TunnelCode::ForeignTunnel:
      return extra.empty() ? "Уже включён другой туннель" : "Уже включён другой туннель: " + extra;
    case TunnelCode::RouteFailed:
      return "Не удалось подготовить маршрут к серверу";
    case TunnelCode::CoreStartFailed:
      return "Не удалось запустить локальный туннель";
    case TunnelCode::KeyProbeFailed:
      return "Ключ не прошёл проверку: сервер или авторизация недоступны";
    case TunnelCode::TunNotReady:
      return "Локальный туннель не поднялся";
    case TunnelCode::EgressFailed:
      return "Сервер не отвечает: выход через туннель не подтверждён";
    case TunnelCode::CleanupFailed:
      return "Сеть не восстановлена. Повторите отключение";
    case TunnelCode::Busy:
      return "Подключение уже идёт";
    case TunnelCode::Protocol:
      return "Переустановите Прокси Дом";
    case TunnelCode::None:
      return extra;
  }
  return {};
}

std::string active_foreign_tunnel(const std::vector<RouteView>& routes) {
  bool have_hardware = false;
  unsigned long hardware_metric = 0xfffffffful;
  for (const auto& row : routes) {
    if (!row.up || row.own || !row.hardware) continue;
    if (row.prefix_length != 0 || row.destination_host != 0) continue;
    if (!have_hardware || row.metric < hardware_metric) {
      hardware_metric = row.metric;
      have_hardware = true;
    }
  }

  std::string best_virtual;
  unsigned long virtual_metric = 0xfffffffful;
  bool have_virtual = false;
  for (const auto& row : routes) {
    if (!row.up || row.own || row.hardware || row.adapter.empty()) continue;
    if (row.prefix_length != 0 || row.destination_host != 0) continue;
    if (have_hardware && row.metric >= hardware_metric) continue;
    if (!have_virtual || row.metric < virtual_metric) {
      virtual_metric = row.metric;
      best_virtual = row.adapter;
      have_virtual = true;
    }
  }
  if (have_virtual) return best_virtual;

  std::map<std::string, int> halves;
  for (const auto& row : routes) {
    if (!row.up || row.own || row.hardware || row.adapter.empty()) continue;
    if (row.prefix_length != 1) continue;
    if (row.destination_host == 0) halves[row.adapter] |= 1;
    if (row.destination_host == 0x80000000u) halves[row.adapter] |= 2;
  }
  for (const auto& item : halves) {
    if (item.second == 3) return item.first;
  }
  return {};
}

std::string encode_ledger(const Ledger& ledger) {
  std::ostringstream out;
  out << "v1\n"
      << "generation=" << ledger.generation << "\n"
      << "phase=" << phase_name(ledger.phase) << "\n"
      << "pid=" << ledger.pid << "\n"
      << "cleanup_verified=" << (ledger.cleanup_verified ? 1 : 0) << "\n"
      << "pin_intended=" << (ledger.pin_intended ? 1 : 0) << "\n"
      << "destination=" << scrub(ledger.pin.destination) << "\n"
      << "interface_luid=" << ledger.pin.interface_luid << "\n"
      << "interface_index=" << ledger.pin.interface_index << "\n"
      << "physical_index=" << ledger.pin.physical_index << "\n"
      << "next_hop=" << scrub(ledger.pin.next_hop) << "\n"
      << "metric=" << ledger.pin.metric << "\n"
      << "adapter_known=" << (ledger.adapter_known ? 1 : 0) << "\n"
      << "adapter_name=" << scrub(ledger.adapter.name) << "\n"
      << "adapter_guid=" << scrub(ledger.adapter.guid) << "\n"
      << "adapter_luid=" << ledger.adapter.luid << "\n"
      << "adapter_index=" << ledger.adapter.if_index << "\n"
      << "config_written=" << (ledger.config_written ? 1 : 0) << "\n";
  for (const auto& route : ledger.routes) {
    out << "route=" << scrub(route.destination) << "/" << route.prefix_length << "/"
        << route.interface_luid << "/" << route.interface_index << "\n";
  }
  return out.str();
}

bool decode_ledger(const std::string& text, Ledger& ledger) {
  if (text.compare(0, 3, "v1\n") != 0 && text != "v1") return false;
  Ledger parsed;
  try {
    parsed.generation = std::stoll(field(text, "generation").empty() ? "0" : field(text, "generation"));
    parsed.phase = phase_from(field(text, "phase"));
    parsed.pid = number_field(text, "pid");
    parsed.cleanup_verified = truth(field(text, "cleanup_verified"));
    parsed.pin_intended = truth(field(text, "pin_intended"));
    parsed.pin.destination = field(text, "destination");
    const std::string luid = field(text, "interface_luid");
    parsed.pin.interface_luid = std::stoull(luid.empty() ? "0" : luid);
    parsed.pin.interface_index = number_field(text, "interface_index");
    parsed.pin.physical_index = number_field(text, "physical_index");
    parsed.pin.next_hop = field(text, "next_hop");
    parsed.pin.metric = number_field(text, "metric");
    parsed.adapter_known = truth(field(text, "adapter_known"));
    parsed.adapter.name = field(text, "adapter_name");
    parsed.adapter.guid = field(text, "adapter_guid");
    const std::string adapter_luid = field(text, "adapter_luid");
    parsed.adapter.luid = std::stoull(adapter_luid.empty() ? "0" : adapter_luid);
    parsed.adapter.if_index = number_field(text, "adapter_index");
    parsed.config_written = truth(field(text, "config_written"));
  } catch (...) {
    return false;
  }

  std::size_t at = 0;
  while (at < text.size()) {
    auto end = text.find('\n', at);
    if (end == std::string::npos) end = text.size();
    const std::string line = text.substr(at, end - at);
    const std::string prefix = "route=";
    if (line.compare(0, prefix.size(), prefix) == 0) {
      const std::string body = line.substr(prefix.size());
      OwnedRoute route;
      const auto first = body.rfind('/');
      if (first == std::string::npos || first == 0) return false;
      const auto second = body.rfind('/', first - 1);
      if (second == std::string::npos || second == 0) return false;
      const auto third = body.rfind('/', second - 1);
      if (third == std::string::npos) return false;
      route.destination = body.substr(0, third);
      try {
        route.prefix_length = std::stoi(body.substr(third + 1, second - third - 1));
        route.interface_luid = std::stoull(body.substr(second + 1, first - second - 1));
        route.interface_index = static_cast<unsigned long>(std::stoul(body.substr(first + 1)));
      } catch (...) {
        return false;
      }
      parsed.routes.push_back(route);
    }
    at = end + 1;
  }
  ledger = parsed;
  return true;
}

TunnelSupervisor::TunnelSupervisor(RouteTable& routes,
                                   EngineHost& engine,
                                   NameResolver& names,
                                   ConnectivityProbe& probe,
                                   SessionFiles& files,
                                   TunnelLog& log,
                                   Sleeper& sleeper)
    : routes_(routes),
      engine_(engine),
      names_(names),
      probe_(probe),
      files_(files),
      log_(log),
      sleeper_(sleeper) {
  published_.phase = TunnelPhase::Idle;
  published_.cleanup_verified = true;
}

void TunnelSupervisor::set_observer(std::function<void(const TunnelSnapshot&)> observer) {
  observer_ = std::move(observer);
}

void TunnelSupervisor::set_hook(std::function<void(ConnectStep)> hook) { hook_ = std::move(hook); }

void TunnelSupervisor::remember(const std::function<void()>& change) {
  std::lock_guard<std::mutex> lock(ledger_mu_);
  change();
  files_.store(ledger_);
}

TunnelSnapshot TunnelSupervisor::snapshot() const {
  std::lock_guard<std::mutex> lock(ledger_mu_);
  return published_;
}

Ledger TunnelSupervisor::ledger_copy() const {
  std::lock_guard<std::mutex> lock(ledger_mu_);
  return ledger_;
}

TunnelSnapshot TunnelSupervisor::publish(TunnelCode code,
                                        const std::string& message,
                                        bool cleanup_verified) {
  TunnelSnapshot snap;
  {
    std::lock_guard<std::mutex> lock(ledger_mu_);
    ledger_.cleanup_verified = cleanup_verified;
    snap.phase = ledger_.phase;
    snap.generation = ledger_.generation;
    snap.code = code;
    snap.message = message;
    snap.cleanup_verified = cleanup_verified;
    published_ = snap;
    if (!cleanup_verified) files_.store(ledger_);
  }
  log_.write(snap.generation, phase_name(snap.phase), code_name(snap.code), routes_.last_error());
  if (observer_) observer_(snap);
  return snap;
}

bool TunnelSupervisor::stop_requested(ConnectStep step, CancelFlag& cancel) {
  if (hook_) hook_(step);
  return cancel.requested();
}

bool TunnelSupervisor::stop_engine_only() {
  if (engine_.alive()) {
    const bool signaled = engine_.request_stop();
    if (signaled) {
      for (int i = 0; i < 20 && engine_.alive(); ++i) sleeper_.sleep_ms(100);
    }
    if (engine_.alive()) engine_.kill();
    for (int i = 0; i < 50 && engine_.alive(); ++i) sleeper_.sleep_ms(100);
  }
  const bool stopped = !engine_.alive();
  engine_.release();
  if (stopped) remember([&] { ledger_.pid = 0; });
  return stopped;
}

bool TunnelSupervisor::restore_resources() {
  const std::int64_t generation = ledger_.generation;
  {
    std::lock_guard<std::mutex> lock(ledger_mu_);
    ledger_.phase = TunnelPhase::Disconnecting;
    ledger_.cleanup_verified = false;
    files_.store(ledger_);
  }

  // Ask the engine to leave, then kill it. Route cleanup waits until the
  // process is gone so it cannot install the halves again.
  if (engine_.alive()) {
    const bool signaled = engine_.request_stop();
    if (signaled) {
      for (int i = 0; i < 20 && engine_.alive(); ++i) sleeper_.sleep_ms(100);
    }
    if (engine_.alive()) engine_.kill();
    for (int i = 0; i < 50 && engine_.alive(); ++i) sleeper_.sleep_ms(100);
  }
  engine_.release();
  engine_.stop_owned_processes();

  bool ok = !engine_.alive();
  PinPlan pin = ledger_.pin;
  const bool pin_intended = ledger_.pin_intended;
  if (pin_intended) {
    if (!routes_.delete_pin(pin) || !routes_.pin_absent(pin)) ok = false;
  }
  const std::string legacy = files_.legacy_pin();
  if (!legacy.empty()) {
    PinPlan old;
    old.destination = legacy;
    if (!routes_.delete_pin(old) || !routes_.pin_absent(old)) ok = false;
    else files_.clear_legacy_pin();
  }

  std::vector<std::uint64_t> luids;
  if (ledger_.adapter_known && ledger_.adapter.luid != 0) luids.push_back(ledger_.adapter.luid);
  for (const auto& route : ledger_.routes) {
    if (route.interface_luid != 0) luids.push_back(route.interface_luid);
  }
  std::vector<OwnedAdapter> adapters;
  if (!routes_.list_own_adapters(adapters)) ok = false;
  for (const auto& adapter : adapters) {
    if (adapter.luid != 0) luids.push_back(adapter.luid);
  }
  std::sort(luids.begin(), luids.end());
  luids.erase(std::unique(luids.begin(), luids.end()), luids.end());
  for (const auto luid : luids) {
    if (!routes_.delete_routes_on_luid(luid) || !routes_.routes_absent(luid)) ok = false;
  }
  if (!routes_.list_own_adapters(adapters)) ok = false;
  for (const auto& adapter : adapters) {
    if (!routes_.remove_adapter(adapter)) ok = false;
  }
  if (!routes_.list_own_adapters(adapters)) ok = false;
  if (!adapters.empty()) ok = false;

  if (ledger_.config_written || files_.config_present()) {
    if (!files_.erase_config() || files_.config_present()) ok = false;
  }
  if (!files_.legacy_pin().empty()) ok = false;

  if (!ok) {
    std::lock_guard<std::mutex> lock(ledger_mu_);
    ledger_.phase = TunnelPhase::Disconnecting;
    ledger_.cleanup_verified = false;
    if (!engine_.alive()) ledger_.pid = 0;
    files_.store(ledger_);
    return false;
  }

  std::lock_guard<std::mutex> lock(ledger_mu_);
  ledger_ = Ledger{};
  ledger_.generation = generation;
  ledger_.phase = TunnelPhase::Idle;
  ledger_.cleanup_verified = true;
  files_.clear();
  return true;
}

TunnelSnapshot TunnelSupervisor::finish(TunnelCode code, const std::string& message, bool quiet) {
  const bool clean = restore_resources();
  if (!clean) return publish(TunnelCode::CleanupFailed, user_message(TunnelCode::CleanupFailed, {}), false);
  if (quiet || code == TunnelCode::None) return publish(TunnelCode::None, message, true);
  return publish(code, message.empty() ? user_message(code, {}) : message, true);
}

BeginResult TunnelSupervisor::begin_connect() {
  BeginResult result;
  {
    std::lock_guard<std::mutex> lock(ledger_mu_);
    if (ledger_.phase != TunnelPhase::Idle || !ledger_.cleanup_verified) {
      result.snap = published_;
      result.snap.code = ledger_.phase == TunnelPhase::Disconnecting ? TunnelCode::CleanupFailed
                                                                      : TunnelCode::Busy;
      result.snap.message = user_message(result.snap.code, {});
      result.accepted = false;
      published_ = result.snap;
      return result;
    }
    ledger_.generation += 1;
    ledger_.phase = TunnelPhase::Connecting;
    ledger_.cleanup_verified = false;
    ledger_.pid = 0;
    ledger_.pin_intended = false;
    ledger_.pin = PinPlan{};
    ledger_.adapter_known = false;
    ledger_.adapter = OwnedAdapter{};
    ledger_.routes.clear();
    ledger_.config_written = false;
    files_.store(ledger_);
    result.accepted = true;
    result.snap.phase = TunnelPhase::Connecting;
    result.snap.generation = ledger_.generation;
    result.snap.cleanup_verified = false;
    published_ = result.snap;
  }
  log_.write(result.snap.generation, "connecting", "", 0);
  return result;
}

TunnelSnapshot TunnelSupervisor::run_connect(const ConnectRequest& request, CancelFlag& cancel) {
  if (ledger_.phase != TunnelPhase::Connecting) return snapshot();
  publish(TunnelCode::None, {}, false);
  if (stop_requested(ConnectStep::Start, cancel)) return finish(TunnelCode::None, {}, true);

  std::vector<RouteView> defaults;
  if (!routes_.list_defaults(defaults)) return finish(TunnelCode::RouteFailed, {}, false);
  const std::string foreign = active_foreign_tunnel(defaults);
  if (!foreign.empty()) {
    return finish(TunnelCode::ForeignTunnel, user_message(TunnelCode::ForeignTunnel, foreign), false);
  }

  ShareLine line;
  std::string error;
  std::string server_ip;
  std::string probe_ip;
  try {
    if (!parse_share_line(request.uri, line, error) || !names_.resolve_ipv4(line.host, server_ip)) {
      return finish(TunnelCode::ResolveFailed, {}, false);
    }
  } catch (...) {
    return finish(TunnelCode::ResolveFailed, {}, false);
  }
  if (stop_requested(ConnectStep::Resolved, cancel)) return finish(TunnelCode::None, {}, true);

  unsigned short probe_port = 0;
  if (!probe_.pick_loopback_port(probe_port)) {
    return finish(TunnelCode::KeyProbeFailed, {}, false);
  }
  const std::string probe_config = build_singbox_probe_config(line, server_ip, probe_port);
  if (probe_config.empty() || !files_.write_config(probe_config)) {
    return finish(TunnelCode::CoreStartFailed, {}, false);
  }
  remember([&] { ledger_.config_written = true; });
  if (stop_requested(ConnectStep::ProbeConfigWritten, cancel)) {
    return finish(TunnelCode::None, {}, true);
  }

  unsigned long pid = 0;
  if (!engine_.launch_suspended(pid)) return finish(TunnelCode::CoreStartFailed, {}, false);
  remember([&] { ledger_.pid = pid; });
  if (!engine_.assign_job()) {
    engine_.kill();
    engine_.release();
    remember([&] { ledger_.pid = 0; });
    return finish(TunnelCode::CoreStartFailed, {}, false);
  }
  if (!engine_.resume()) return finish(TunnelCode::CoreStartFailed, {}, false);
  if (stop_requested(ConnectStep::ProbeLaunched, cancel)) {
    return finish(TunnelCode::None, {}, true);
  }

  if (!names_.resolve_ipv4("cp.cloudflare.com", probe_ip)) {
    return finish(TunnelCode::ResolveFailed, {}, false);
  }
  const bool key_ok =
      probe_.prove_socks(probe_port, probe_ip, [&] { return cancel.requested(); });
  if (cancel.requested()) return finish(TunnelCode::None, {}, true);
  if (!key_ok || !stop_engine_only()) {
    return finish(TunnelCode::KeyProbeFailed, {}, false);
  }
  if (stop_requested(ConnectStep::ProbePassed, cancel)) {
    return finish(TunnelCode::None, {}, true);
  }

  // The no-route probe can take several seconds. Re-check the competing-tunnel
  // gate immediately before the first system route mutation.
  if (!routes_.list_defaults(defaults)) return finish(TunnelCode::RouteFailed, {}, false);
  const std::string foreign_again = active_foreign_tunnel(defaults);
  if (!foreign_again.empty()) {
    return finish(TunnelCode::ForeignTunnel, user_message(TunnelCode::ForeignTunnel, foreign_again), false);
  }

  PinPlan pin;
  if (!routes_.plan_hardware_pin(server_ip, pin)) return finish(TunnelCode::RouteFailed, {}, false);
  remember([&] {
    ledger_.pin_intended = true;
    ledger_.pin = pin;
  });
  if (!routes_.add_pin(ledger_.pin)) return finish(TunnelCode::RouteFailed, {}, false);
  if (stop_requested(ConnectStep::Pinned, cancel)) return finish(TunnelCode::None, {}, true);

  if (!names_.resolve_ipv4("cp.cloudflare.com", probe_ip)) return finish(TunnelCode::ResolveFailed, {}, false);
  const std::string config = build_singbox_config(line, server_ip, request.direct_domains);
  if (config.empty() || !files_.write_config(config)) return finish(TunnelCode::CoreStartFailed, {}, false);
  if (stop_requested(ConnectStep::ConfigWritten, cancel)) return finish(TunnelCode::None, {}, true);

  pid = 0;
  if (!engine_.launch_suspended(pid)) return finish(TunnelCode::CoreStartFailed, {}, false);
  remember([&] { ledger_.pid = pid; });
  if (stop_requested(ConnectStep::Launched, cancel)) return finish(TunnelCode::None, {}, true);

  if (!engine_.assign_job()) {
    engine_.kill();
    engine_.release();
    remember([&] { ledger_.pid = 0; });
    return finish(TunnelCode::CoreStartFailed, {}, false);
  }
  if (stop_requested(ConnectStep::JobAssigned, cancel)) return finish(TunnelCode::None, {}, true);
  if (!engine_.resume()) return finish(TunnelCode::CoreStartFailed, {}, false);
  if (stop_requested(ConnectStep::Resumed, cancel)) return finish(TunnelCode::None, {}, true);

  OwnedAdapter adapter;
  std::vector<OwnedRoute> halves;
  bool ready = false;
  for (int i = 0; i < 50; ++i) {
    if (cancel.requested()) return finish(TunnelCode::None, {}, true);
    if (!engine_.alive()) return finish(TunnelCode::TunNotReady, {}, false);
    if (routes_.tun_ready(adapter, halves)) {
      ready = true;
      break;
    }
    sleeper_.sleep_ms(100);
  }
  if (!ready) return finish(TunnelCode::TunNotReady, {}, false);
  remember([&] {
    ledger_.adapter_known = true;
    ledger_.adapter = adapter;
    ledger_.routes = halves;
  });
  if (stop_requested(ConnectStep::TunReady, cancel)) return finish(TunnelCode::None, {}, true);

  const unsigned long if_index = adapter.if_index;
  const bool proved = routes_.prove_exit(if_index, probe_ip, [&] { return cancel.requested(); });
  if (cancel.requested()) return finish(TunnelCode::None, {}, true);
  if (!proved) return finish(TunnelCode::EgressFailed, {}, false);
  if (stop_requested(ConnectStep::Proven, cancel)) return finish(TunnelCode::None, {}, true);

  {
    std::lock_guard<std::mutex> lock(ledger_mu_);
    ledger_.phase = TunnelPhase::Connected;
    files_.store(ledger_);
  }
  return publish(TunnelCode::None, {}, false);
}

TunnelSnapshot TunnelSupervisor::disconnect(CancelFlag& cancel) {
  (void)cancel;
  return finish(TunnelCode::None, {}, true);
}

TunnelSnapshot TunnelSupervisor::watchdog(CancelFlag& cancel) {
  // Idle and verified means this process owns no routes. A stale cancel bit
  // must not republish Idle every watchdog tick.
  if (ledger_.phase == TunnelPhase::Idle && ledger_.cleanup_verified) return snapshot();
  const bool restore_pending = ledger_.phase == TunnelPhase::Disconnecting ||
                               (ledger_.phase == TunnelPhase::Idle && !ledger_.cleanup_verified);
  if (cancel.requested() || restore_pending) return finish(TunnelCode::None, {}, true);
  if (ledger_.phase != TunnelPhase::Connected) return snapshot();
  if (!engine_.alive()) return finish(TunnelCode::None, kLost, false);
  OwnedAdapter adapter;
  std::vector<OwnedRoute> halves;
  if (!routes_.tun_ready(adapter, halves)) return finish(TunnelCode::None, kLost, false);
  if (ledger_.pin_intended) {
    PinPlan now;
    if (!routes_.plan_hardware_pin(ledger_.pin.destination, now) ||
        now.interface_index != ledger_.pin.interface_index) {
      return finish(TunnelCode::None, kChanged, false);
    }
  }
  return snapshot();
}

TunnelSnapshot TunnelSupervisor::reconcile(CancelFlag& cancel) {
  (void)cancel;
  Ledger loaded;
  const int rc = files_.load(loaded);
  if (rc > 0) {
    std::lock_guard<std::mutex> lock(ledger_mu_);
    ledger_ = loaded;
  }
  return finish(TunnelCode::None, {}, true);
}
