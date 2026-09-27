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

bool extract_domains(const std::string& json, std::vector<std::string>& domains, std::string& error) {
  const std::string pattern = "\"direct_domains\"";
  const auto at = json.find(pattern);
  if (at == std::string::npos) return true;
  auto bracket = json.find('[', at + pattern.size());
  if (bracket == std::string::npos) {
    error = "direct_domains";
    return false;
  }
  auto end = json.find(']', bracket);
  if (end == std::string::npos) {
    error = "direct_domains";
    return false;
  }
  std::string body = json.substr(bracket + 1, end - bracket - 1);
  std::size_t i = 0;
  while (i < body.size()) {
    while (i < body.size() && (body[i] == ' ' || body[i] == ',' || body[i] == '\n')) ++i;
    if (i >= body.size()) break;
    if (body[i] != '"') {
      error = "direct_domains";
      return false;
    }
    ++i;
    std::string host;
    while (i < body.size() && body[i] != '"') {
      host.push_back(body[i]);
      ++i;
    }
    if (i >= body.size()) {
      error = "direct_domains";
      return false;
    }
    ++i;
    if (!domain_allowed(host)) {
      error = "direct_domains";
      return false;
    }
    if (domains.size() >= 64) {
      error = "direct_domains";
      return false;
    }
    domains.push_back(host);
  }
  return true;
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
  if (!extract_domains(json, out.direct_domains, error)) return false;
  return true;
}

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
  int port = 443;
  if (!port_token.empty() && port_token.find_first_not_of("0123456789") == std::string::npos) {
    port = std::stoi(port_token);
  } else if (!port_token.empty()) {
    out.server_ports = port_token;
  }
  const std::string mport = query_value(query, "mport");
  if (!mport.empty()) out.server_ports = mport;
  const std::string hop = query_value(query, "mportHopInt");
  if (!hop.empty() && hop.find_first_not_of("0123456789") == std::string::npos) {
    out.hop_interval = hop + "s";
  }
  if (port <= 0 || port > 65535) {
    error = "port";
    return false;
  }
  out.port = port;
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
    if (out.security == "reality" && out.public_key.empty()) {
      error = "reality";
      return false;
    }
  }
  (void)fragment;
  return true;
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

std::string build_singbox_config(const ShareLine& line,
                                 const std::string& server_ip,
                                 const std::vector<std::string>& domains) {
  if (server_ip.empty() || server_ip.find(':') != std::string::npos) return {};
  std::ostringstream outbound;
  if (line.scheme == "hysteria2") {
    outbound << "{\"type\":\"hysteria2\",\"tag\":\"proxy\",\"server\":\"" << json_escape(server_ip)
             << "\",\"server_port\":" << line.port;
    if (!line.server_ports.empty()) {
      outbound << ",\"server_ports\":[\"" << json_escape(line.server_ports) << "\"]";
    }
    if (!line.hop_interval.empty()) {
      outbound << ",\"hop_interval\":\"" << json_escape(line.hop_interval) << "\"";
    }
    outbound << ",\"password\":\"" << json_escape(line.password) << "\"";
    if (lower_copy(line.obfs) == "salamander") {
      outbound << ",\"obfs\":{\"type\":\"salamander\",\"password\":\"" << json_escape(line.obfs_password)
               << "\"}";
    }
    outbound << ",\"tls\":{\"enabled\":true,\"server_name\":\"" << json_escape(line.sni) << "\",\"insecure\":"
             << (line.insecure ? "true" : "false") << "}}";
  } else {
    outbound << "{\"type\":\"vless\",\"tag\":\"proxy\",\"server\":\"" << json_escape(server_ip)
             << "\",\"server_port\":" << line.port << ",\"uuid\":\"" << json_escape(line.uuid) << "\"";
    if (!line.flow.empty()) outbound << ",\"flow\":\"" << json_escape(line.flow) << "\"";
    outbound << ",\"tls\":{\"enabled\":true,\"server_name\":\"" << json_escape(line.sni) << "\",\"insecure\":"
             << (line.insecure ? "true" : "false") << ",\"utls\":{\"enabled\":true,\"fingerprint\":\""
             << json_escape(line.fingerprint) << "\"}";
    if (line.security == "reality") {
      outbound << ",\"reality\":{\"enabled\":true,\"public_key\":\"" << json_escape(line.public_key)
               << "\",\"short_id\":\"" << json_escape(line.short_id) << "\"}";
    }
    outbound << "}}";
  }

  std::ostringstream rules;
  rules << "{\"ip_cidr\":[\"10.0.0.0/8\",\"172.16.0.0/12\",\"192.168.0.0/16\",\"127.0.0.0/8\","
           "\"fc00::/7\",\"fe80::/10\"],\"outbound\":\"direct\"}";
  for (const auto& domain : domains) {
    if (!domain_allowed(domain)) continue;
    rules << ",{\"domain_suffix\":[\"" << json_escape(domain) << "\"],\"outbound\":\"direct\"}";
  }

  std::ostringstream config;
  config << "{"
         << "\"log\":{\"level\":\"info\"},"
         << "\"inbounds\":[{\"type\":\"tun\",\"tag\":\"tun-in\",\"interface_name\":\"ProxyDomTun\","
         << "\"address\":[\"198.18.0.1/30\"],\"auto_route\":true,\"strict_route\":true,"
         << "\"dns_mode\":\"hijack\",\"dns_address\":[\"198.18.0.2\"],"
         << "\"route_address\":[\"0.0.0.0/1\",\"128.0.0.0/1\"],"
         << "\"route_exclude_address\":[\"10.0.0.0/8\",\"172.16.0.0/12\",\"192.168.0.0/16\","
         << "\"127.0.0.0/8\",\"fc00::/7\",\"fe80::/10\"]}],"
         << "\"outbounds\":[" << outbound.str() << ",{\"type\":\"direct\",\"tag\":\"direct\"}],"
         << "\"route\":{\"auto_detect_interface\":true,\"final\":\"proxy\",\"rules\":[" << rules.str() << "]}"
         << "}";
  return config.str();
}
