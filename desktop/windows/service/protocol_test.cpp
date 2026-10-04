#include "protocol.h"

#include <iostream>
#include <string>

namespace {

int g_failed = 0;

void expect(bool ok, const char* label) {
  if (ok) return;
  std::cerr << "FAIL " << label << "\n";
  ++g_failed;
}

}  // namespace

int main() {
  const std::string hello = "{\"command\":\"hello\",\"protocol_version\":3}";
  const auto framed = encode_frame(hello);
  expect(framed.size() == 4 + hello.size(), "frame size");
  std::string buffer = framed + framed;
  std::string json;
  std::string error;
  expect(take_frame(buffer, json, error), "first frame");
  expect(json == hello, "first json");
  expect(take_frame(buffer, json, error), "second frame");
  expect(buffer.empty(), "buffer drained");

  std::string huge(kFrameMaxBody + 1, 'a');
  expect(encode_frame(huge).empty(), "reject oversize encode");
  std::string bad(4, '\0');
  const auto over = kFrameMaxBody + 1;
  bad[0] = static_cast<char>(over & 0xff);
  bad[1] = static_cast<char>((over >> 8) & 0xff);
  bad[2] = static_cast<char>((over >> 16) & 0xff);
  bad[3] = static_cast<char>((over >> 24) & 0xff);
  error.clear();
  expect(!take_frame(bad, json, error) && error == "frame", "reject oversize length");

  ClientCommand command;
  error.clear();
  expect(parse_command(hello, command, error), "parse hello");
  expect(command.command == "hello" && command.protocol_version == 3, "hello fields");

  error.clear();
  expect(!parse_command("{\"command\":\"connect\",\"outbounds\":[]}", command, error), "reject outbounds");

  const std::string short_connect =
      "{\"command\":\"connect\",\"protocol_version\":3,"
      "\"uri\":\"hy2://secret@cdn.example:443\","
      "\"direct_domains\":[\"lan.example\",\"bad host\"]}";
  error.clear();
  expect(parse_command(short_connect, command, error), "short connect survives a bad name");
  expect(command.command == "connect" && command.protocol_version == 3, "connect fields");
  expect(command.uri == "hy2://secret@cdn.example:443", "connect keeps the share line");
  expect(command.direct_domains.size() == 1 && command.direct_domains[0] == "lan.example",
         "bad direct name is dropped");

  std::string long_connect =
      "{\"command\":\"connect\",\"protocol_version\":3,"
      "\"uri\":\"hy2://secret@cdn.example:443\",\"direct_domains\":[";
  for (std::size_t i = 0; i < 70; ++i) {
    if (i != 0) long_connect += ',';
    long_connect += "\"d" + std::to_string(i) + ".example\"";
  }
  long_connect += ",\"../x\"]}";
  error.clear();
  expect(parse_command(long_connect, command, error), "long connect is still a command");
  expect(command.uri == "hy2://secret@cdn.example:443", "long connect keeps the share line");
  // The sites screen ships 120 default-on suffixes. A 64 cap dropped the tail,
  // which is where every steam* name sits, so Steam stayed on the proxy.
  expect(command.direct_domains.size() == 70, "70 exclusion names all survive");
  expect(!command.direct_domains_truncated, "70 names do not trip the cap");
  expect(encode_frame(long_connect).size() == 4 + long_connect.size(), "long connect still frames");

  std::string over_connect =
      "{\"command\":\"connect\",\"protocol_version\":3,"
      "\"uri\":\"hy2://secret@cdn.example:443\",\"direct_domains\":[";
  for (std::size_t i = 0; i < kMaxDirectDomains + 8; ++i) {
    if (i != 0) over_connect += ',';
    over_connect += "\"o" + std::to_string(i) + ".example\"";
  }
  over_connect += "]}";
  error.clear();
  expect(parse_command(over_connect, command, error), "over-cap connect is still a command");
  expect(command.direct_domains.size() == kMaxDirectDomains, "direct names stop at the cap");
  expect(command.direct_domains_truncated, "over-cap list reports truncation");

  const std::string routed_connect =
      "{\"command\":\"connect\",\"protocol_version\":3,"
      "\"uri\":\"hy2://secret@cdn.example:443\","
      "\"direct_domains\":[\"steamserver.net\"],"
      "\"force_proxy_domains\":[\"youtube.com\",\"bad host\"],"
      "\"udp_direct\":1}";
  error.clear();
  expect(parse_command(routed_connect, command, error), "routed connect parses");
  expect(command.force_proxy_domains.size() == 1 && command.force_proxy_domains[0] == "youtube.com",
         "force-proxy list keeps good names only");
  expect(command.udp_direct, "udp_direct 1 is true");
  error.clear();
  expect(parse_command(
             "{\"command\":\"connect\",\"protocol_version\":3,\"uri\":\"hy2://s@a:443\","
             "\"udp_direct\":0}",
             command, error),
         "udp_direct 0 parses");
  expect(!command.udp_direct, "udp_direct 0 is false");
  error.clear();
  expect(parse_command(
             "{\"command\":\"connect\",\"protocol_version\":3,\"uri\":\"hy2://s@a:443\"}",
             command, error),
         "absent udp_direct parses");
  expect(!command.udp_direct, "absent udp_direct stays off");

  ShareLine line;
  error.clear();
  expect(!parse_share_line("trojan://pass@host:443", line, error), "reject trojan");
  expect(!parse_share_line("vless://uuid@[2001:db8::1]:443", line, error), "reject ipv6 host");

  const std::string hy2 =
      "hy2://secret%2Bpass@cdn.example:443?obfs=salamander&obfs-password=hide&mport=1000-2000&mportHopInt=30&sni=cdn.example#Home";
  expect(parse_share_line(hy2, line, error), "parse hy2");
  expect(line.scheme == "hysteria2", "hy2 scheme");
  expect(line.password == "secret+pass", "hy2 password");
  expect(line.obfs == "salamander", "salamander");
  expect(line.port == 1000, "hop starts at the low port");
  expect(line.server_ports == "1000:2000", "hop ports");
  expect(line.hop_interval == "30s", "hop interval");

  const auto config = build_singbox_config(line, "203.0.113.10", {"lan.example"}, {}, false, 0, "");
  expect(config.find("\"stack\":\"system\"") != std::string::npos, "windows tun uses the system adapter");
  expect(config.find("\"auto_route\":false") != std::string::npos, "engine does not own routes");
  expect(config.find("\"auto_route\":true") == std::string::npos, "auto_route stays off");
  expect(config.find("route_address") == std::string::npos, "engine installs no prefixes");
  expect(config.find("::/0") == std::string::npos, "no v6 default");
  expect(config.find("198.18.0.1/30") != std::string::npos, "tun prefix");
  expect(config.find("198.18.0.2") != std::string::npos, "dns address");
  expect(config.find("salamander") != std::string::npos, "obfs in config");
  expect(config.find("lan.example") != std::string::npos, "direct domain");
  expect(config.find("\"server_ports\":[\"1000:2000\"]") != std::string::npos, "hop range uses a colon");

  // Game traffic is UDP to bare IPs whose addresses change, so the tunnel is
  // bypassed by protocol instead of by a list that would rot.
  const auto udp_config =
      build_singbox_config(line, "203.0.113.10", {"steamserver.net"}, {"youtube.com"}, true, 0, "");
  expect(udp_config.find("{\"network\":\"udp\",\"outbound\":\"direct\"}") != std::string::npos,
         "udp bypass rule is emitted");
  expect(build_singbox_config(line, "203.0.113.10", {}, {}, false, 0, "")
             .find("\"network\":\"udp\"") == std::string::npos,
         "no udp bypass when the window did not ask");
  const auto force_at = udp_config.find("youtube.com");
  const auto udp_at = udp_config.find("\"network\":\"udp\"");
  const auto direct_at = udp_config.find("steamserver.net");
  expect(force_at != std::string::npos && udp_at != std::string::npos && direct_at != std::string::npos,
         "routed config carries all three rules");
  expect(force_at < udp_at, "force-proxy sits above the udp bypass");
  expect(direct_at < udp_at, "site exclusions sit above the udp bypass");
  const auto force_rule = udp_config.find("youtube.com");
  expect(force_rule != std::string::npos &&
             udp_config.find("\"domain_suffix\":[\"youtube.com\"],\"outbound\":\"proxy\"") != std::string::npos,
         "force-proxy row routes to proxy, not direct");

  // The broker reads its routing counters off a loopback clash api. Without it
  // there is nothing in the journal that says where a game's UDP actually went.
  expect(config.find("clash_api") == std::string::npos, "no controller without a port");
  const auto api_config = build_singbox_config(line, "203.0.113.10", {}, {}, true, 19090, "abc123");
  expect(api_config.find("\"external_controller\":\"127.0.0.1:19090\"") != std::string::npos,
         "controller listens on loopback only");
  expect(api_config.find("\"secret\":\"abc123\"") != std::string::npos, "controller carries the secret");
  expect(api_config.find("0.0.0.0:19090") == std::string::npos,
         "controller is not on a routable address");
  expect(api_config.find("{\"network\":\"udp\",\"outbound\":\"direct\"}") != std::string::npos,
         "counters do not displace the udp bypass");
  const auto quoted = build_singbox_config(line, "203.0.113.10", {}, {}, false, 19091, "he\"llo\\there");
  expect(quoted.find("\"secret\":\"he\\\"llo\\\\there\"") != std::string::npos,
         "a quote or a backslash in the secret cannot break the config");
  const auto no_api = build_singbox_config(line, "203.0.113.10", {}, {}, false, 0, "");
  expect(no_api.find("\"experimental\":{") != std::string::npos, "experimental block is always present");
  expect(no_api.find("\"experimental\":{}") == std::string::npos, "experimental block is never empty");

  ShareLine slash;
  error.clear();
  expect(parse_share_line("hy2://secret@cdn.example:443/?sni=cdn.example", slash, error), "slash after port parses");
  expect(slash.port == 443 && slash.server_ports.empty(), "slash is not a port range");
  const auto slash_config = build_singbox_config(slash, "203.0.113.10", {}, {}, false, 0, "");
  expect(slash_config.find("server_ports") == std::string::npos, "plain port omits server_ports");
  expect(!parse_share_line("hy2://secret@cdn.example:443abc", slash, error), "junk port is refused");
  expect(error == "port", "junk port error");
  expect(config.find("1000-2000") == std::string::npos, "hop range is not a hyphen");
  expect(config.find("\"action\":\"hijack-dns\"") != std::string::npos, "dns hijack rule");
  expect(config.find("\"server\":\"1.1.1.1\"") != std::string::npos, "dns server");
  expect(config.find("secret+pass") != std::string::npos, "password reaches the engine config");
  expect(config.find("172.19.0.1") == std::string::npos, "tun prefix stays outside 172.16/12");
  expect(build_singbox_config(line, "2001:db8::1", {}, {}, false, 0, "").empty(), "refuse ipv6 pin");
  const auto probe = build_singbox_probe_config(line, "203.0.113.10", 17890);
  expect(probe.find("\"type\":\"mixed\"") != std::string::npos, "probe has loopback proxy");
  expect(probe.find("\"listen\":\"127.0.0.1\"") != std::string::npos, "probe is loopback only");
  expect(probe.find("\"listen_port\":17890") != std::string::npos, "probe port");
  expect(probe.find("\"type\":\"tun\"") == std::string::npos, "probe has no tun");
  expect(probe.find("auto_route") == std::string::npos, "probe changes no routes");

  ShareLine vless;
  error.clear();
  const std::string vless_uri =
      "vless://11111111-2222-3333-4444-555555555555@edge.example:443?security=reality&pbk=pub&sid=abcd&sni=edge.example&flow=xtls-rprx-vision&fp=chrome";
  expect(parse_share_line(vless_uri, vless, error), "parse vless");
  const auto vless_config = build_singbox_config(vless, "203.0.113.11", {}, {}, false, 0, "");
  expect(vless_config.find("\"public_key\":\"pub\"") != std::string::npos, "reality public key");
  expect(vless_config.find("private_key") == std::string::npos, "no server private key");
  expect(vless_config.find("xtls-rprx-vision") != std::string::npos, "flow");

  const auto restored = state_event_v2(7, "idle", "", "", true);
  expect(restored.find("\"cleanup_verified\":true") != std::string::npos, "verified idle flag");
  expect(restored.find("\"code\":null") != std::string::npos, "empty code is null");
  const auto failed = state_event_v2(7, "disconnecting", "cleanup_failed", "Сеть не восстановлена", false);
  expect(failed.find("\"cleanup_verified\":false") != std::string::npos, "unverified cleanup flag");
  expect(failed.find("cleanup_failed") != std::string::npos, "cleanup code");
  const auto ack = ack_event("connect", false, 7, "foreign_tunnel", "Уже включён другой туннель");
  expect(ack.find("\"event\":\"ack\"") != std::string::npos, "ack event");
  expect(ack.find("\"accepted\":false") != std::string::npos, "ack rejected");
  expect(ack.find("foreign_tunnel") != std::string::npos, "ack code");

  expect(own_adapter_name(L"ProxyDomTun"), "own tun");
  expect(own_adapter_name(L"teremokhy2"), "legacy tun");
  expect(!own_adapter_name(L"WireGuard"), "foreign tun");
  expect(domain_allowed("lan.example"), "domain");
  expect(!domain_allowed("http://lan.example"), "domain rejects a url");
  expect(!domain_allowed("../x"), "domain rejects dots");
  expect(prove_generation_due(0, 1), "first generation is proved");
  expect(!prove_generation_due(1, 1), "the same generation is not proved twice");
  expect(prove_generation_due(1, 2), "the next server is proved");
  expect(!prove_generation_due(0, 0), "generation 0 is not a proof");

  if (g_failed != 0) {
    std::cerr << g_failed << " failed\n";
    return 1;
  }
  std::cout << "ok\n";
  return 0;
}
