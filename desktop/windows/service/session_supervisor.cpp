#include "session_supervisor.h"

#include "log_sanitizer.h"
#include "protocol.h"

#include <algorithm>
#include <cctype>
#include <chrono>
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

std::string lower_copy(std::string text) {
  for (char& ch : text) ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
  return text;
}

unsigned long digits_after(const std::string& text, std::size_t at) {
  if (at >= text.size() || text[at] < '0' || text[at] > '9') return 0;
  unsigned long value = 0;
  int count = 0;
  while (at < text.size() && text[at] >= '0' && text[at] <= '9' && count < 6) {
    value = value * 10u + static_cast<unsigned long>(text[at] - '0');
    ++at;
    ++count;
  }
  if (count == 0 || value == 0 || value > 65535ul) return 0;
  return value;
}

unsigned long win32_in_text(const std::string& text) {
  const std::string lower = lower_copy(text);
  const char* keys[] = {"win32=", "winerror=", "errno="};
  for (const char* key : keys) {
    const auto at = lower.find(key);
    if (at == std::string::npos) continue;
    const auto value = digits_after(lower, at + std::char_traits<char>::length(key));
    if (value != 0) return value;
  }
  const auto err = lower.find("error ");
  if (err == std::string::npos) return 0;
  return digits_after(lower, err + 6);
}

bool text_says_name_taken(const std::string& text) {
  return lower_copy(text).find("already exists") != std::string::npos;
}

bool tun_name(const std::string& name) { return name == "ProxyDomTun"; }

bool tun_usable(const OwnedAdapter& adapter) {
  return tun_name(adapter.name) && adapter.up && adapter.luid != 0 && adapter.if_index != 0;
}

}  // namespace

TunWaitClass classify_tun_wait(const TunWaitView& view) {
  if (!view.process_alive) return {"process_died", view.process_exit};
  int named = 0;
  int usable = 0;
  int not_up = 0;
  for (const auto& adapter : view.adapters) {
    if (!tun_name(adapter.name)) continue;
    ++named;
    if (tun_usable(adapter)) ++usable;
    else ++not_up;
  }
  // A second ProxyDomTun, or sing-box saying the name is taken, is not "still down".
  if (named > 1 || text_says_name_taken(view.engine_text)) return {"adapter_name_conflict", 0};
  if (not_up > 0) return {"adapter_state_not_up", 0};
  const unsigned long parsed = win32_in_text(view.engine_text);
  if (parsed != 0 && usable == 0) return {"wintun_create_failed", parsed};
  if (!view.list_ok) return {"adapter_not_found", view.list_error};
  if (usable > 0) return {"adapter_up", 0};
  return {"adapter_not_found", 0};
}

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
    case TunnelCode::CoreExited:
      return "core_exited";
    case TunnelCode::TunInitTimeout:
      return "tun_init_timeout";
    case TunnelCode::EgressTimeout:
      return "egress_timeout";
    case TunnelCode::AuthRejected:
      return "auth_rejected";
    case TunnelCode::InvalidProfile:
      return "invalid_profile";
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
      return "Обнаружен активный туннель";
    case TunnelCode::RouteFailed:
      return "Сбой сетевого стека";
    case TunnelCode::CoreStartFailed:
      return "Сбой локальной службы туннеля";
    case TunnelCode::CoreExited:
      return "Сбой локальной службы туннеля";
    case TunnelCode::TunInitTimeout:
      return "Сбой сетевого адаптера туннеля";
    case TunnelCode::EgressTimeout:
      return "Узел недоступен";
    case TunnelCode::AuthRejected:
      return "Ключ не принят сервером";
    case TunnelCode::InvalidProfile:
      return "Неверный порт сервера";
    case TunnelCode::KeyProbeFailed:
      return "Ключ не принят сервером или узел недоступен";
    case TunnelCode::TunNotReady:
      return "Виртуальный адаптер недоступен";
    case TunnelCode::EgressFailed:
      return "Не удалось подтвердить доступность узла. Попробуйте другой сервер";
    case TunnelCode::CleanupFailed:
      return "Ошибка восстановления сети. Перезапустите службу";
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

void TunnelSupervisor::set_flow_factory(
    std::function<std::unique_ptr<FlowProbe>(unsigned short, const std::string&)> factory) {
  flow_factory_ = std::move(factory);
}

namespace {

// Enough traffic to mean "this is a real flow", not a DNS reply or a TLS hello.
constexpr std::uint64_t kFlowNoticeBytes = 64u * 1024u;
constexpr std::uint64_t kFlowSampleMs = 5000;
constexpr std::uint64_t kFlowSummaryMs = 15000;

std::uint64_t now_ms() {
  return static_cast<std::uint64_t>(
      std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now().time_since_epoch())
          .count());
}

}  // namespace

void TunnelSupervisor::sample_flows() {
  if (!flows_) return;
  const std::uint64_t stamp = now_ms();
  // The service loop ticks about every two seconds; polling on its own clock
  // keeps the sample rate independent of how often the pipe wakes us.
  if (stamp - flow_last_sample_ms_ < kFlowSampleMs) return;
  flow_last_sample_ms_ = stamp;

  FlowSample sample;
  if (!flows_->poll(sample)) {
    // One line per session: the engine may not be listening yet right after start.
    if (!flow_api_reported_) {
      flow_api_reported_ = true;
      log_.write(ledger_.generation, "flow", "api_unreachable", flows_->last_error());
    }
    return;
  }
  flow_api_reported_ = false;

  for (const auto& row : sample.rows) {
    const std::string key = row.network + ":" + row.chain;
    flow_up_[key] += row.upload;
    flow_down_[key] += row.download;

    const std::string notice = key + "|" + row.destination + "|" + row.process;
    if (row.upload + row.download < kFlowNoticeBytes) continue;
    if (!flow_announced_.insert(notice).second) continue;
    log_.write(ledger_.generation, "flow_seen",
               "net=" + journal_token(row.network) + " chain=" + journal_token(row.chain) +
                   " dst=" + journal_token(row.destination) + " proc=" + journal_token(row.process) +
                   " up=" + std::to_string(row.upload) + " dn=" + std::to_string(row.download),
               0);
  }

  if (stamp - flow_last_summary_ms_ >= kFlowSummaryMs) {
    flow_last_summary_ms_ = stamp;
    emit_flow_summary("flow_summary");
  }
}

void TunnelSupervisor::emit_flow_summary(const char* event) {
  if (flow_up_.empty() && flow_down_.empty()) return;
  std::string code;
  for (const auto& entry : flow_down_) {
    if (!code.empty()) code += " ";
    code += journal_token(entry.first) + "=dn:" + std::to_string(entry.second) + "/up:" +
            std::to_string(flow_up_[entry.first]);
  }
  log_.write(ledger_.generation, event, code, 0);
}

void TunnelSupervisor::set_ready_observer(std::function<void(std::int64_t)> observer) {
  ready_observer_ = std::move(observer);
}

void TunnelSupervisor::note_user_proof(bool ok, std::int64_t generation) {
  std::lock_guard<std::mutex> lock(ledger_mu_);
  if (generation == 0 || generation != ledger_.generation) return;
  proof_generation_ = generation;
  proof_result_ = ok ? 1 : -1;
}

void TunnelSupervisor::accept_user_proof_for_tests(bool enabled) { test_user_proof_ = enabled; }

bool TunnelSupervisor::wait_user_proof(std::int64_t generation, CancelFlag& cancel) {
  for (int i = 0; i < 150; ++i) {
    if (cancel.requested()) return false;
    {
      std::lock_guard<std::mutex> lock(ledger_mu_);
      if (proof_generation_ == generation && proof_result_ == 1) return true;
      if (proof_generation_ == generation && proof_result_ == -1) return false;
    }
    sleeper_.sleep_ms(100);
  }
  return false;
}

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
  if (ledger_.phase == TunnelPhase::Connected) {
    flow_last_sample_ms_ = 0;  // the closing sample is not a periodic one
    sample_flows();
    emit_flow_summary("flow_total");
  }
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

void TunnelSupervisor::note_tun_timeout() {
  TunWaitView view;
  view.process_alive = engine_.alive();
  view.process_exit = view.process_alive ? 0 : engine_.exit_code();
  // The first 256 characters are only the gateway INFO. The create error is later in the same tail.
  view.engine_text = sanitize_engine_output_full(engine_.output_tail());
  view.list_ok = routes_.list_own_adapters(view.adapters);
  view.list_error = view.list_ok ? 0 : routes_.last_error();

  log_.write(ledger_.generation, "tun_diag", view.process_alive ? "process_alive" : "process_died",
             view.process_alive ? 0 : view.process_exit);
  // service.log lines are 512 bytes. A numbered chunk stays inside that line.
  constexpr std::size_t kStderrChunk = 240;
  int part = 1;
  for (std::size_t at = 0; at < view.engine_text.size(); at += kStderrChunk, ++part) {
    const std::size_t n = std::min(kStderrChunk, view.engine_text.size() - at);
    std::string code = std::to_string(part);
    code.push_back(' ');
    code.append(view.engine_text, at, n);
    log_.write(ledger_.generation, "tun_stderr", code, view.process_exit);
  }
  if (!view.list_ok) {
    log_.write(ledger_.generation, "tun_adapter", "list_failed", view.list_error);
  } else if (view.adapters.empty()) {
    log_.write(ledger_.generation, "tun_adapter", "none", 0);
  } else {
    for (const auto& adapter : view.adapters) {
      std::string name = adapter.name.empty() ? std::string("-") : adapter.name;
      for (char& ch : name) {
        if (ch == ' ' || ch == ',' || ch == '\r' || ch == '\n') ch = '_';
      }
      std::ostringstream code;
      code << name << ",up=" << (adapter.up ? 1 : 0) << ",luid=" << adapter.luid
           << ",if=" << adapter.if_index;
      log_.write(ledger_.generation, "tun_adapter", code.str(), adapter.up ? 1ul : 0ul);
    }
  }
  const TunWaitClass found = classify_tun_wait(view);
  log_.write(ledger_.generation, "tun_init_timeout", found.code, found.win32);
}

void TunnelSupervisor::gate(const char* step, const char* outcome) {
  std::string code = step == nullptr ? std::string{} : step;
  if (outcome != nullptr && outcome[0] != '\0') {
    code.push_back('=');
    code += outcome;
  }
  log_.write(ledger_.generation, "gate", code, 0);
}

TunnelSnapshot TunnelSupervisor::run_connect(const ConnectRequest& request, CancelFlag& cancel) {
  if (ledger_.phase != TunnelPhase::Connecting) return snapshot();
  publish(TunnelCode::None, {}, false);
  if (stop_requested(ConnectStep::Start, cancel)) return finish(TunnelCode::None, {}, true);

  gate("foreign_tunnel", nullptr);
  std::vector<RouteView> defaults;
  if (!routes_.list_defaults(defaults)) return finish(TunnelCode::RouteFailed, {}, false);
  const std::string foreign = active_foreign_tunnel(defaults);
  if (!foreign.empty()) {
    log_.write(ledger_.generation, "foreign_adapter", foreign, 0);
    return finish(TunnelCode::ForeignTunnel, user_message(TunnelCode::ForeignTunnel, {}), false);
  }
  gate("foreign_tunnel", "ok");

  gate("resolve", nullptr);
  ShareLine line;
  std::string error;
  std::string server_ip;
  std::string probe_ip;
  try {
    if (!parse_share_line(request.uri, line, error)) {
      if (error == "port") {
        std::string value = line.server_ports;
        if (value.size() > 32) value.resize(32);
        if (value.find('@') != std::string::npos) value = "port";
        log_.write(ledger_.generation, "profile_parse_failed", value, 0);
        return finish(TunnelCode::InvalidProfile, {}, false);
      }
      return finish(TunnelCode::ResolveFailed, {}, false);
    }
    if (!names_.resolve_ipv4(line.host, server_ip)) {
      return finish(TunnelCode::ResolveFailed, {}, false);
    }
  } catch (...) {
    return finish(TunnelCode::ResolveFailed, {}, false);
  }
  gate("resolve", "ok");
  if (stop_requested(ConnectStep::Resolved, cancel)) return finish(TunnelCode::None, {}, true);

  gate("core", nullptr);
  // The loopback controller is what tells us, per connection, whether a game's
  // UDP left direct or inside the proxy stream. It carries a per-session secret
  // and is only reachable on 127.0.0.1.
  unsigned short api_port = 0;
  std::string api_secret;
  flows_.reset();
  flow_up_.clear();
  flow_down_.clear();
  flow_announced_.clear();
  flow_last_sample_ms_ = 0;
  flow_last_summary_ms_ = 0;
  flow_api_reported_ = false;
  if (flow_factory_ && probe_.pick_loopback_port(api_port)) {
    api_secret = make_api_secret();
    flows_ = flow_factory_(api_port, api_secret);
  }
  const std::string config =
      build_singbox_config(line, server_ip, request.direct_domains, request.force_proxy_domains,
                           request.udp_direct, flows_ ? api_port : 0, api_secret);
  if (config.empty() || !files_.write_config(config)) {
    const unsigned long win32 = config.empty() ? 13u : files_.last_error();
    log_.write(ledger_.generation, "core_config_failed", "", win32);
    return finish(TunnelCode::CoreStartFailed, {}, false);
  }
  if (flows_) {
    log_.write(ledger_.generation, "flow", "api_port=" + std::to_string(api_port), 0);
  }
  remember([&] { ledger_.config_written = true; });
  if (stop_requested(ConnectStep::ConfigWritten, cancel)) return finish(TunnelCode::None, {}, true);

  auto log_start_failure = [&](const char* fallback) {
    const char* stage = engine_.start_stage();
    if (stage == nullptr || stage[0] == '\0') stage = fallback;
    log_.write(ledger_.generation, stage, "", engine_.last_error());
  };

  unsigned long pid = 0;
  if (!engine_.launch_suspended(pid)) {
    log_start_failure("core_create_process_failed");
    return finish(TunnelCode::CoreStartFailed, {}, false);
  }
  remember([&] { ledger_.pid = pid; });
  if (stop_requested(ConnectStep::Launched, cancel)) return finish(TunnelCode::None, {}, true);
  if (!engine_.assign_job()) {
    log_start_failure("core_job_assign_failed");
    engine_.kill();
    engine_.release();
    remember([&] { ledger_.pid = 0; });
    return finish(TunnelCode::CoreStartFailed, {}, false);
  }
  if (stop_requested(ConnectStep::JobAssigned, cancel)) return finish(TunnelCode::None, {}, true);
  if (!engine_.resume()) {
    log_start_failure("core_resume_failed");
    return finish(TunnelCode::CoreStartFailed, {}, false);
  }
  if (stop_requested(ConnectStep::Resumed, cancel)) return finish(TunnelCode::None, {}, true);

  OwnedAdapter adapter;
  bool found = false;
  for (int i = 0; i < 50; ++i) {
    if (cancel.requested()) return finish(TunnelCode::None, {}, true);
    if (!engine_.alive()) {
      const std::string stderr_text = sanitize_engine_output(engine_.output_tail());
      log_.write(ledger_.generation, "core_exited", stderr_text, engine_.exit_code());
      return finish(TunnelCode::CoreExited, {}, false);
    }
    if (routes_.find_own_adapter(adapter)) {
      found = true;
      break;
    }
    sleeper_.sleep_ms(100);
  }
  if (!found) {
    note_tun_timeout();
    return finish(TunnelCode::TunInitTimeout, {}, false);
  }
  gate("core", "ok");
  remember([&] {
    ledger_.adapter_known = true;
    ledger_.adapter = adapter;
  });

  // The adapter wait can take a few seconds. Re-check before the first route write.
  gate("foreign_tunnel", nullptr);
  if (!routes_.list_defaults(defaults)) {
    log_.write(ledger_.generation, "routes", "pin_failed", routes_.last_error());
    return finish(TunnelCode::RouteFailed, {}, false);
  }
  const std::string foreign_again = active_foreign_tunnel(defaults);
  if (!foreign_again.empty()) {
    log_.write(ledger_.generation, "foreign_adapter", foreign_again, 0);
    return finish(TunnelCode::ForeignTunnel, user_message(TunnelCode::ForeignTunnel, {}), false);
  }
  gate("foreign_tunnel", "ok");

  gate("routes", nullptr);
  PinPlan pin;
  if (!routes_.plan_hardware_pin(server_ip, pin)) {
    log_.write(ledger_.generation, "routes", "pin_failed", routes_.last_error());
    return finish(TunnelCode::RouteFailed, {}, false);
  }
  remember([&] {
    ledger_.pin_intended = true;
    ledger_.pin = pin;
  });
  if (!routes_.add_pin(ledger_.pin)) {
    log_.write(ledger_.generation, "routes", "pin_failed", routes_.last_error());
    return finish(TunnelCode::RouteFailed, {}, false);
  }
  if (stop_requested(ConnectStep::Pinned, cancel)) return finish(TunnelCode::None, {}, true);

  gate("resolve", nullptr);
  if (!names_.resolve_ipv4("cp.cloudflare.com", probe_ip)) return finish(TunnelCode::ResolveFailed, {}, false);
  gate("resolve", "ok");
  OwnedRoute canary;
  if (!routes_.add_canary(adapter, probe_ip, canary)) {
    log_.write(ledger_.generation, "routes", "canary_failed", routes_.last_error());
    return finish(TunnelCode::RouteFailed, {}, false);
  }
  remember([&] { ledger_.routes = {canary}; });

  gate("egress", nullptr);
  const bool canary_ok = routes_.fetch_canary(probe_ip, [&] { return cancel.requested(); });
  if (cancel.requested()) return finish(TunnelCode::None, {}, true);
  if (!canary_ok) {
    const std::string stderr_text = engine_.output_tail();
    if (engine_reported_auth_failure(stderr_text)) {
      log_.write(ledger_.generation, "egress", "auth_rejected", 0);
      return finish(TunnelCode::AuthRejected, {}, false);
    }
    log_.write(ledger_.generation, "egress", "timeout", 3500);
    return finish(TunnelCode::EgressTimeout, {}, false);
  }
  gate("egress", "ok");
  if (!routes_.delete_canary(canary)) {
    log_.write(ledger_.generation, "routes", "canary_failed", routes_.last_error());
    return finish(TunnelCode::RouteFailed, {}, false);
  }
  remember([&] { ledger_.routes.clear(); });

  std::vector<OwnedRoute> capture;
  if (!routes_.install_capture(adapter, capture)) {
    log_.write(ledger_.generation, "routes", "capture_failed", routes_.last_error());
    return finish(TunnelCode::RouteFailed, "Сбой применения маршрутов", false);
  }
  remember([&] { ledger_.routes = capture; });
  OwnedAdapter seen;
  std::vector<OwnedRoute> halves;
  if (!routes_.tun_ready(seen, halves)) {
    note_tun_timeout();
    return finish(TunnelCode::TunInitTimeout, {}, false);
  }
  log_.write(ledger_.generation, "routes", "capture_installed", static_cast<unsigned long>(capture.size()));
  gate("routes", "ok");
  if (stop_requested(ConnectStep::TunReady, cancel)) return finish(TunnelCode::None, {}, true);

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
  sample_flows();
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
