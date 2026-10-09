#include "protocol.h"

#include <cctype>
#include <cstdio>
#include <sstream>

namespace {

std::string json_escape(const std::string& text) {
  std::string out;
  out.reserve(text.size() + 8);
  for (unsigned char c : text) {
    switch (c) {
      case '\\':
        out += "\\\\";
        break;
      case '"':
        out += "\\\"";
        break;
      case '\n':
        out += "\\n";
        break;
      case '\r':
        out += "\\r";
        break;
      case '\t':
        out += "\\t";
        break;
      default:
        if (c < 0x20) {
          char buf[8];
          std::snprintf(buf, sizeof(buf), "\\u%04x", c);
          out += buf;
        } else {
          out.push_back(static_cast<char>(c));
        }
    }
  }
  return out;
}

std::string percent_decode(const std::string& in) {
  std::string out;
  out.reserve(in.size());
  for (std::size_t i = 0; i < in.size(); ++i) {
    if (in[i] == '%' && i + 2 < in.size()) {
      auto hex = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
      };
      const int hi = hex(in[i + 1]);
      const int lo = hex(in[i + 2]);
      if (hi >= 0 && lo >= 0) {
        out.push_back(static_cast<char>(hi * 16 + lo));
        i += 2;
        continue;
      }
    }
    out.push_back(in[i]);
  }
  return out;
}

std::string trim_copy(const std::string& text) {
  std::size_t begin = 0;
  while (begin < text.size() && std::isspace(static_cast<unsigned char>(text[begin]))) {
    ++begin;
  }
  std::size_t end = text.size();
  while (end > begin && std::isspace(static_cast<unsigned char>(text[end - 1]))) {
    --end;
  }
  return text.substr(begin, end - begin);
}

std::string lower_copy(std::string text) {
  for (char& c : text) {
    c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  }
  return text;
}

bool extract_string_field(const std::string& json,
                          const std::string& key,
                          std::string& value,
                          bool& present) {
  const std::string pattern = "\"" + key + "\"";
  const auto at = json.find(pattern);
  if (at == std::string::npos) {
    present = false;
    return true;
  }
  present = true;
  auto colon = json.find(':', at + pattern.size());
  if (colon == std::string::npos) return false;
  auto i = colon + 1;
  while (i < json.size() && std::isspace(static_cast<unsigned char>(json[i]))) ++i;
  if (i >= json.size()) return false;
  if (json.compare(i, 4, "null") == 0) {
    value.clear();
    return true;
  }
  if (json[i] != '"') return false;
  ++i;
  std::string raw;
  while (i < json.size()) {
    if (json[i] == '\\' && i + 1 < json.size()) {
      const char n = json[i + 1];
      if (n == '"' || n == '\\' || n == '/') raw.push_back(n);
      else if (n == 'n') raw.push_back('\n');
      else if (n == 'r') raw.push_back('\r');
      else if (n == 't') raw.push_back('\t');
      else raw.push_back(n);
      i += 2;
      continue;
    }
    if (json[i] == '"') break;
    raw.push_back(json[i]);
    ++i;
  }
  value = raw;
  return true;
}

bool extract_int_field(const std::string& json, const std::string& key, std::int64_t& value, bool& present) {
  const std::string pattern = "\"" + key + "\"";
  const auto at = json.find(pattern);
  if (at == std::string::npos) {
    present = false;
    return true;
  }
  present = true;
  auto colon = json.find(':', at + pattern.size());
  if (colon == std::string::npos) return false;
  auto i = colon + 1;
  while (i < json.size() && std::isspace(static_cast<unsigned char>(json[i]))) ++i;
  if (i >= json.size() || !std::isdigit(static_cast<unsigned char>(json[i]))) return false;
  value = 0;
  while (i < json.size() && std::isdigit(static_cast<unsigned char>(json[i]))) {
    value = value * 10 + (json[i] - '0');
    ++i;
  }
  return true;
}

bool extract_string_array(const std::string& json,
                          const std::string& key,
                          bool (*allowed)(const std::string&),
                          std::size_t cap,
                          std::vector<std::string>& out,
                          bool& truncated,
                          std::string& error) {
  const std::string pattern = "\"" + key + "\"";
  const auto at = json.find(pattern);
  if (at == std::string::npos) return true;
  auto bracket = json.find('[', at + pattern.size());
  if (bracket == std::string::npos) {
    error = key;
    return false;
  }
  auto end = json.find(']', bracket);
  if (end == std::string::npos) {
    error = key;
    return false;
  }
  std::string body = json.substr(bracket + 1, end - bracket - 1);
  std::size_t i = 0;
  while (i < body.size()) {
    while (i < body.size() && (body[i] == ' ' || body[i] == ',' || body[i] == '\n')) ++i;
    if (i >= body.size()) break;
    if (body[i] != '"') {
      error = key;
      return false;
    }
    ++i;
    std::string host;
    while (i < body.size() && body[i] != '"') {
      host.push_back(body[i]);
      ++i;
    }
    if (i >= body.size()) {
      error = key;
      return false;
    }
    ++i;
    if (!allowed(host)) continue;
    if (out.size() >= cap) {
      truncated = true;
      continue;
    }
    out.push_back(host);
  }
  return true;
}

bool extract_domains(const std::string& json, std::vector<std::string>& domains, bool& truncated, std::string& error) {
  return extract_string_array(json, "direct_domains", domain_allowed, kMaxDirectDomains,
                              domains, truncated, error);
}

bool extract_force_proxy(const std::string& json, std::vector<std::string>& domains, std::string& error) {
  bool truncated = false;
  return extract_string_array(json, "force_proxy_domains", domain_allowed, kMaxDirectDomains,
                              domains, truncated, error);
}

std::string query_value(const std::string& query, const std::string& key) {
  std::size_t i = 0;
  while (i < query.size()) {
    auto amp = query.find('&', i);
    if (amp == std::string::npos) amp = query.size();
    auto eq = query.find('=', i);
    if (eq != std::string::npos && eq < amp) {
      if (percent_decode(query.substr(i, eq - i)) == key) {
        return percent_decode(query.substr(eq + 1, amp - eq - 1));
      }
    }
    i = amp + 1;
  }
  return {};
}

}  // namespace

std::string encode_frame(const std::string& json) {
  if (json.size() > kFrameMaxBody) return {};
  std::string out(4 + json.size(), '\0');
  const auto n = static_cast<std::uint32_t>(json.size());
  out[0] = static_cast<char>(n & 0xff);
  out[1] = static_cast<char>((n >> 8) & 0xff);
  out[2] = static_cast<char>((n >> 16) & 0xff);
  out[3] = static_cast<char>((n >> 24) & 0xff);
  out.replace(4, json.size(), json);
  return out;
}

bool take_frame(std::string& buffer, std::string& json, std::string& error) {
  if (buffer.size() < 4) return false;
  const auto n = static_cast<std::uint32_t>(static_cast<unsigned char>(buffer[0])) |
                 (static_cast<std::uint32_t>(static_cast<unsigned char>(buffer[1])) << 8) |
                 (static_cast<std::uint32_t>(static_cast<unsigned char>(buffer[2])) << 16) |
                 (static_cast<std::uint32_t>(static_cast<unsigned char>(buffer[3])) << 24);
  if (n > kFrameMaxBody) {
    error = "frame";
    buffer.clear();
    return false;
  }
  if (buffer.size() < 4u + n) return false;
  json.assign(buffer, 4, n);
  buffer.erase(0, 4u + n);
  return true;
}

bool domain_allowed(const std::string& host) {
  if (host.empty() || host.size() > 253) return false;
  for (unsigned char c : host) {
    if (std::isalnum(c) || c == '.' || c == '-' || c == '_') continue;
    return false;
  }
  if (host.front() == '.' || host.back() == '.') return false;
  return host.find("..") == std::string::npos;
}

bool own_adapter_name(const std::wstring& name) {
  return name == L"ProxyDomTun" || name == L"teremokhy2";
}

bool parse_command(const std::string& json, ClientCommand& out, std::string& error) {
  if (json.find("\"outbounds\"") != std::string::npos ||
      json.find("\"inbounds\"") != std::string::npos) {
    error = "config";
    return false;
  }
  // [out] may be a reused struct. Without this reset the exclusion list of a
  // previous command leaks into the next one.
  out.direct_domains.clear();
  out.direct_domains_truncated = false;
  bool present = false;
  if (!extract_string_field(json, "command", out.command, present) || !present) {
    error = "command";
    return false;
  }
  extract_string_field(json, "uri", out.uri, present);
  std::int64_t version = 0;
  bool has_version = false;
  if (!extract_int_field(json, "protocol_version", version, has_version)) {
    error = "protocol_version";
    return false;
  }
  if (has_version) out.protocol_version = static_cast<int>(version);
  std::int64_t generation = 0;
  bool has_gen = false;
  if (!extract_int_field(json, "generation", generation, has_gen)) {
    error = "generation";
    return false;
  }
  out.generation = generation;
  if (!extract_string_field(json, "message", out.message, present)) {
    error = "message";
    return false;
  }
  if (!present) out.message.clear();
  if (!extract_domains(json, out.direct_domains, out.direct_domains_truncated, error)) return false;
  if (!extract_force_proxy(json, out.force_proxy_domains, error)) return false;
  // The window sends 0/1; anything else is not a request for UDP bypass.
  std::int64_t udp_direct = 0;
  bool has_udp_direct = false;
  if (!extract_int_field(json, "udp_direct", udp_direct, has_udp_direct)) {
    error = "udp_direct";
    return false;
  }
  out.udp_direct = has_udp_direct && udp_direct != 0;
  return true;
}

namespace {

std::string cut_port_spec(std::string text) {
  const auto end = text.find_first_of("/?#");
  if (end != std::string::npos) text.resize(end);
  return text;
}

bool port_number(const std::string& text, int& port) {
  if (text.empty() || text.size() > 5) return false;
  if (text.find_first_not_of("0123456789") != std::string::npos) return false;
  try {
    const int value = std::stoi(text);
    if (value < 1 || value > 65535) return false;
    port = value;
    return true;
  } catch (...) {
    return false;
  }
}

bool apply_port_spec(const std::string& raw, ShareLine& out, std::string& error) {
  const std::string spec = cut_port_spec(raw);
  if (spec.empty()) {
    out.port = 443;
    out.server_ports.clear();
    return true;
  }
  const auto dash = spec.find('-');
  const auto colon = spec.find(':');
  if (dash != std::string::npos && colon != std::string::npos) {
    error = "port";
    out.server_ports = spec.substr(0, 32);
    return false;
  }
  const auto sep = dash != std::string::npos ? dash : colon;
  if (sep != std::string::npos) {
    if (spec.find(spec[sep], sep + 1) != std::string::npos) {
      error = "port";
      out.server_ports = spec.substr(0, 32);
      return false;
    }
    int start = 0;
    int end = 0;
    if (!port_number(spec.substr(0, sep), start) || !port_number(spec.substr(sep + 1), end) || start > end) {
      error = "port";
      out.server_ports = spec.substr(0, 32);
      return false;
    }
    out.port = start;
    out.server_ports = std::to_string(start) + ":" + std::to_string(end);
    return true;
  }
  int port = 0;
  if (!port_number(spec, port)) {
    error = "port";
    out.server_ports = spec.substr(0, 32);
    return false;
  }
  out.port = port;
  out.server_ports.clear();
  return true;
}

}  // namespace

bool parse_share_line(const std::string& raw, ShareLine& out, std::string& error) {
  const std::string text = trim_copy(raw);
  const auto scheme_end = text.find("://");
  if (scheme_end == std::string::npos || scheme_end == 0) {
    error = "scheme";
    return false;
  }
  std::string scheme = lower_copy(text.substr(0, scheme_end));
  if (scheme == "hy2") scheme = "hysteria2";
  if (scheme != "hysteria2" && scheme != "vless") {
    error = "scheme";
    return false;
  }
  std::string rest = text.substr(scheme_end + 3);
  std::string fragment;
  const auto hash = rest.find('#');
  if (hash != std::string::npos) {
    fragment = percent_decode(rest.substr(hash + 1));
    rest = rest.substr(0, hash);
  }
  const auto at = rest.find('@');
  if (at == std::string::npos) {
    error = "auth";
    return false;
  }
  const std::string user = percent_decode(rest.substr(0, at));
  std::string hostport = rest.substr(at + 1);
  std::string query;
  const auto q = hostport.find('?');
  if (q != std::string::npos) {
    query = hostport.substr(q + 1);
    hostport = hostport.substr(0, q);
  }
  std::string host;
  std::string port_token;
  if (!hostport.empty() && hostport[0] == '[') {
    const auto bracket = hostport.find(']');
    if (bracket == std::string::npos) {
      error = "host";
      return false;
    }
    host = hostport.substr(1, bracket - 1);
    if (bracket + 1 < hostport.size() && hostport[bracket + 1] == ':') {
      port_token = hostport.substr(bracket + 2);
    }
  } else {
    const auto colon = hostport.rfind(':');
    if (colon == std::string::npos) {
      host = hostport;
    } else {
      host = hostport.substr(0, colon);
      port_token = hostport.substr(colon + 1);
    }
  }
  if (host.empty()) {
    error = "host";
    return false;
  }
  if (host.find(':') != std::string::npos) {
    error = "ipv6";
    return false;
  }
  out = ShareLine{};
  out.scheme = scheme;
  out.host = host;
  out.sni = query_value(query, "sni");
  if (out.sni.empty()) out.sni = host;
  out.insecure = query_value(query, "insecure") == "1" || query_value(query, "allowInsecure") == "1";
  std::string port_spec = port_token;
  const std::string mport = query_value(query, "mport");
  if (!mport.empty()) port_spec = mport;
  if (!apply_port_spec(port_spec, out, error)) return false;
  const std::string hop = query_value(query, "mportHopInt");
  if (!hop.empty() && hop.find_first_not_of("0123456789") == std::string::npos) {
    out.hop_interval = hop + "s";
  }
  if (scheme == "hysteria2") {
    if (user.empty()) {
      error = "auth";
      return false;
    }
    const auto colon = user.find(':');
    if (colon == std::string::npos) {
      out.password = user;
    } else {
      const std::string username = user.substr(0, colon);
      const std::string password = user.substr(colon + 1);
      out.password = password.empty() ? username : username + ":" + password;
    }
    out.obfs = query_value(query, "obfs");
    out.obfs_password = query_value(query, "obfs-password");
  } else {
    out.uuid = user;
    if (out.uuid.empty()) {
      error = "auth";
      return false;
    }
    out.flow = query_value(query, "flow");
    out.security = lower_copy(query_value(query, "security"));
    out.public_key = query_value(query, "pbk");
    out.short_id = query_value(query, "sid");
    out.fingerprint = query_value(query, "fp");
    if (out.fingerprint.empty()) out.fingerprint = "chrome";
    // The same defaults the Dart builder uses, so one link cannot be described
    // two ways depending on which side of the process boundary reads it.
    out.network = lower_copy(query_value(query, "type"));
    if (out.network.empty()) out.network = lower_copy(query_value(query, "net"));
    if (out.network.empty()) out.network = "tcp";
    out.path = query_value(query, "path");
    out.ws_host = query_value(query, "host");
    out.alpn = query_value(query, "alpn");
    if (out.security.empty()) out.security = "tls";
    if (out.security == "reality" && out.public_key.empty()) {
      error = "reality";
      return false;
    }
  }
  (void)fragment;
  return true;
}

std::string json_or_null(const std::string& text) {
  if (text.empty()) return "null";
  return "\"" + json_escape(text) + "\"";
}

std::string state_event_v2(std::int64_t generation,
                           const std::string& state,
                           const std::string& code,
                           const std::string& message,
                           bool cleanup_verified) {
  std::ostringstream out;
  out << "{\"event\":\"state\",\"generation\":" << generation << ",\"state\":\"" << json_escape(state)
      << "\",\"code\":" << json_or_null(code) << ",\"message\":" << json_or_null(message)
      << ",\"cleanup_verified\":" << (cleanup_verified ? "true" : "false") << "}";
  return out.str();
}

std::string ack_event(const std::string& command,
                      bool accepted,
                      std::int64_t generation,
                      const std::string& code,
                      const std::string& message) {
  std::ostringstream out;
  out << "{\"event\":\"ack\",\"command\":\"" << json_escape(command) << "\",\"accepted\":"
      << (accepted ? "true" : "false") << ",\"generation\":" << generation << ",\"code\":" << json_or_null(code)
      << ",\"message\":" << json_or_null(message) << "}";
  return out.str();
}

std::string tun_ready_event(std::int64_t generation) {
  std::ostringstream out;
  out << "{\"event\":\"tun_ready\",\"generation\":" << generation
      << ",\"state\":\"connecting\",\"code\":null,\"message\":null,\"cleanup_verified\":false}";
  return out.str();
}

std::string state_event(std::int64_t generation, const std::string& state, const std::string* message) {
  std::ostringstream out;
  out << "{\"event\":\"state\",\"generation\":" << generation << ",\"state\":\"" << json_escape(state)
      << "\",\"message\":";
  if (message == nullptr) out << "null";
  else out << "\"" << json_escape(*message) << "\"";
  out << "}";
  return out.str();
}

namespace {

std::string json_string_array(const std::vector<std::string>& values) {
  std::ostringstream out;
  bool first = true;
  for (const auto& value : values) {
    if (!domain_allowed(value)) continue;
    if (!first) out << ',';
    first = false;
    out << '"' << json_escape(value) << '"';
  }
  return out.str();
}

// Outbound object for proxydom-engine. VLESS is carried by the in-process
// v2ray-core; a transport or security that core does not have is described
// here and refused by the process (`error transport` / `error security`), not
// rewritten as a TCP dial.
std::string engine_outbound(const ShareLine& line, const std::string& server_ip) {
  if (server_ip.empty() || server_ip.find(':') != std::string::npos) return {};
  std::ostringstream outbound;
  if (line.scheme == "hysteria2") {
    outbound << "{\"type\":\"hysteria2\",\"server\":\"" << json_escape(server_ip) << "\",\"server_port\":" << line.port;
    if (!line.server_ports.empty()) {
      outbound << ",\"server_ports\":\"" << json_escape(line.server_ports) << "\"";
    }
    if (!line.hop_interval.empty()) {
      outbound << ",\"hop_interval\":\"" << json_escape(line.hop_interval) << "\"";
    }
    outbound << ",\"password\":\"" << json_escape(line.password) << "\",\"sni\":\"" << json_escape(line.sni)
             << "\",\"insecure\":" << (line.insecure ? "true" : "false");
    if (lower_copy(line.obfs) == "salamander") {
      outbound << ",\"obfs\":\"salamander\",\"obfs_password\":\"" << json_escape(line.obfs_password) << "\"";
    }
    outbound << "}";
  } else {
    outbound << "{\"type\":\"vless\",\"server\":\"" << json_escape(server_ip) << "\",\"server_port\":" << line.port
             << ",\"uuid\":\"" << json_escape(line.uuid) << "\"";
    if (!line.flow.empty()) outbound << ",\"flow\":\"" << json_escape(line.flow) << "\"";
    outbound << ",\"sni\":\"" << json_escape(line.sni) << "\",\"insecure\":" << (line.insecure ? "true" : "false")
             << ",\"fingerprint\":\"" << json_escape(line.fingerprint) << "\""
             << ",\"security\":\"" << json_escape(line.security) << "\""
             << ",\"network\":\"" << json_escape(line.network) << "\"";
    // Without these a vless:// over WebSocket cannot be described at all, and
    // the row that needs them is exactly the one subscriptions hand out.
    if (!line.path.empty()) outbound << ",\"path\":\"" << json_escape(line.path) << "\"";
    if (!line.ws_host.empty()) outbound << ",\"host\":\"" << json_escape(line.ws_host) << "\"";
    if (!line.alpn.empty()) outbound << ",\"alpn\":\"" << json_escape(line.alpn) << "\"";
    if (line.security == "reality") {
      outbound << ",\"public_key\":\"" << json_escape(line.public_key) << "\",\"short_id\":\""
               << json_escape(line.short_id) << "\"";
    }
    outbound << "}";
  }
  return outbound.str();
}

}  // namespace

std::string build_engine_probe_config(const ShareLine& line,
                                      const std::string& server_ip,
                                      unsigned short listen_port) {
  if (listen_port == 0) return {};
  const std::string outbound = engine_outbound(line, server_ip);
  if (outbound.empty()) return {};
  std::ostringstream config;
  config << "{\"log_level\":\"warn\",\"probe\":true,\"socks_listen\":\"127.0.0.1:" << listen_port
         << "\",\"routing_applied\":false,\"dns_hijack\":false,\"outbound\":" << outbound << "}";
  return config.str();
}

std::string build_engine_config(const ShareLine& line,
                                const std::string& server_ip,
                                const std::vector<std::string>& domains,
                                const std::vector<std::string>& force_proxy_domains,
                                bool udp_direct,
                                unsigned short api_port,
                                const std::string& api_secret) {
  const std::string outbound = engine_outbound(line, server_ip);
  if (outbound.empty()) return {};

  // Domain lists are recorded in the order the sites screen already uses:
  // force-proxy names, then exclusions, then the UDP flag. The engine applies
  // them: force-proxy wins over a direct suffix and over UDP bypass.
  // auto_route stays false: C++ installs the capture routes.
  std::ostringstream config;
  config << "{"
         << "\"log_level\":\"info\","
         << "\"probe\":false,"
         << "\"socks_listen\":\"127.0.0.1:10808\","
         << "\"tun\":{\"name\":\"" << kTunName << "\",\"address\":\"" << kTunIpv4
         << "/30\",\"dns\":\"198.18.0.2\","
         << "\"mtu\":1280,\"auto_route\":false},"
         << "\"force_proxy_domains\":[" << json_string_array(force_proxy_domains) << "],"
         << "\"direct_domains\":[" << json_string_array(domains) << "],"
         << "\"udp_direct\":" << (udp_direct ? "true" : "false") << ","
         << "\"dns_hijack\":true,"
         << "\"routing_applied\":true,"
         << "\"api_port\":" << api_port << ","
         << "\"api_secret\":\"" << json_escape(api_secret) << "\","
         << "\"outbound\":" << outbound << "}";
  return config.str();
}
