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
      "\"udp_mode\":\"direct_non_forced\","
      "\"udp_direct\":1}";
  error.clear();
  expect(parse_command(routed_connect, command, error), "routed connect parses");
  expect(command.force_proxy_domains.size() == 1 && command.force_proxy_domains[0] == "youtube.com",
         "force-proxy list keeps good names only");
  expect(command.udp_mode == "direct_non_forced", "the explicit udp mode is parsed");
  expect(command.udp_direct, "udp_direct 1 is true for an old window");
  error.clear();
  expect(parse_command(
             "{\"command\":\"connect\",\"protocol_version\":3,\"uri\":\"hy2://s@a:443\","
             "\"udp_mode\":\"nonsense\",\"udp_direct\":0}",
             command, error),
         "an unknown udp mode still parses");
  expect(command.udp_mode == "proxy_all", "an unknown udp mode falls back to proxy_all");
  expect(!command.udp_direct, "udp_direct 0 is false");
  error.clear();
  expect(parse_command(
             "{\"command\":\"connect\",\"protocol_version\":3,\"uri\":\"hy2://s@a:443\"}",
             command, error),
         "absent udp_direct parses");
  expect(!command.udp_direct, "absent udp_direct stays off");
  expect(command.udp_mode.empty(), "an absent udp mode is left for the default");

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

  const auto config = build_engine_config(line, "203.0.113.10", {"lan.example"}, {}, "proxy_all", 0, "");
  expect(config.find("\"name\":\"ProxyDomTun\"") != std::string::npos, "tun name");
  expect(config.find("\"auto_route\":false") != std::string::npos, "engine does not own routes");
  expect(config.find("\"auto_route\":true") == std::string::npos, "auto_route stays off");
  expect(config.find("route_address") == std::string::npos, "engine installs no prefixes");
  expect(config.find("::/0") == std::string::npos, "no v6 default");
  expect(config.find("198.18.0.1/30") != std::string::npos, "tun prefix");
  expect(config.find("198.18.0.2") != std::string::npos, "dns address");
  expect(config.find("salamander") != std::string::npos, "obfs in config");
  expect(config.find("lan.example") != std::string::npos, "direct domain");
  expect(config.find("\"server_ports\":\"1000:2000\"") != std::string::npos, "hop range uses a colon");
  expect(config.find("\"routing_applied\":true") != std::string::npos, "routing is applied");
  expect(config.find("\"dns_hijack\":true") != std::string::npos, "dns hijack is applied");

  // The lists reach the document in the order the sites screen uses, and the
  // engine applies them: force-proxy wins over a direct suffix and over UDP.
  const auto udp_config =
      build_engine_config(line, "203.0.113.10", {"steamserver.net"}, {"youtube.com"}, "direct_non_forced", 0, "");
  expect(udp_config.find("\"udp_mode\":\"direct_non_forced\"") != std::string::npos, "game mode is recorded as a policy");
  expect(build_engine_config(line, "203.0.113.10", {}, {}, "proxy_all", 0, "")
             .find("\"udp_mode\":\"proxy_all\"") != std::string::npos,
         "the default keeps UDP on the tunnel");
  const auto force_at = udp_config.find("youtube.com");
  const auto direct_at = udp_config.find("steamserver.net");
  const auto mode_at = udp_config.find("\"udp_mode\":\"direct_non_forced\"");
  expect(force_at != std::string::npos && mode_at != std::string::npos && direct_at != std::string::npos,
         "config carries force-proxy, exclusions, and the udp mode");
  expect(force_at < mode_at, "force-proxy sits above the udp mode");
  expect(direct_at < mode_at, "site exclusions sit above the udp mode");
  expect(udp_config.find("\"force_proxy_domains\":[\"youtube.com\"]") != std::string::npos,
         "force-proxy names are recorded");

  expect(config.find("\"api_port\":0") != std::string::npos, "no controller without a port");
  const auto api_config = build_engine_config(line, "203.0.113.10", {}, {}, "direct_non_forced", 19090, "abc123");
  expect(api_config.find("\"api_port\":19090") != std::string::npos, "api port is recorded");
  expect(api_config.find("\"api_secret\":\"abc123\"") != std::string::npos, "api secret is recorded");
  expect(api_config.find("0.0.0.0:19090") == std::string::npos, "controller is not on a routable address");
  expect(api_config.find("\"udp_mode\":\"direct_non_forced\"") != std::string::npos, "api fields do not drop the udp mode");
  const auto quoted = build_engine_config(line, "203.0.113.10", {}, {}, "proxy_all", 19091, "he\"llo\\there");
  expect(quoted.find("\"api_secret\":\"he\\\"llo\\\\there\"") != std::string::npos,
         "a quote or a backslash in the secret cannot break the config");
  const auto no_api = build_engine_config(line, "203.0.113.10", {}, {}, "proxy_all", 0, "");
  expect(no_api.find("\"routing_applied\":true") != std::string::npos, "routing flag is always present");
  expect(no_api.find("\"api_port\":0") != std::string::npos, "absent api is port 0");

  ShareLine slash;
  error.clear();
  expect(parse_share_line("hy2://secret@cdn.example:443/?sni=cdn.example", slash, error), "slash after port parses");
  expect(slash.port == 443 && slash.server_ports.empty(), "slash is not a port range");
  const auto slash_config = build_engine_config(slash, "203.0.113.10", {}, {}, "proxy_all", 0, "");
  expect(slash_config.find("server_ports") == std::string::npos, "plain port omits server_ports");
  expect(!parse_share_line("hy2://secret@cdn.example:443abc", slash, error), "junk port is refused");
  expect(error == "port", "junk port error");
  expect(config.find("1000-2000") == std::string::npos, "hop range is not a hyphen");
  expect(config.find("hijack-dns") == std::string::npos, "dns hijack is not a sing-box rule");
  expect(config.find("\"dns_hijack\":true") != std::string::npos, "dns hijack flag is true");
  expect(config.find("secret+pass") != std::string::npos, "password reaches the engine config");
  expect(config.find("172.19.0.1") == std::string::npos, "tun prefix stays outside 172.16/12");
  expect(build_engine_config(line, "2001:db8::1", {}, {}, "proxy_all", 0, "").empty(), "refuse ipv6 pin");
  const auto probe = build_engine_probe_config(line, "203.0.113.10", 17890);
  expect(probe.find("\"probe\":true") != std::string::npos, "probe flag");
  expect(probe.find("\"socks_listen\":\"127.0.0.1:17890\"") != std::string::npos, "probe is loopback only");
  expect(probe.find("ProxyDomTun") == std::string::npos, "probe has no tun");
  expect(probe.find("auto_route") == std::string::npos, "probe changes no routes");

  ShareLine vless;
  error.clear();
  const std::string vless_uri =
      "vless://11111111-2222-3333-4444-555555555555@edge.example:443?security=reality&pbk=pub&sid=abcd&sni=edge.example&flow=xtls-rprx-vision&fp=chrome";
  expect(parse_share_line(vless_uri, vless, error), "parse vless");
  const auto vless_config = build_engine_config(vless, "203.0.113.11", {}, {}, "proxy_all", 0, "");
  expect(vless_config.find("\"public_key\":\"pub\"") != std::string::npos, "reality public key");
  expect(vless_config.find("private_key") == std::string::npos, "no server private key");
  expect(vless_config.find("xtls-rprx-vision") != std::string::npos, "flow");
  // The parser carries the share-link word, not a core preset: `fp=chrome` is
  // what the link says, and translating it to the uTLS preset the core accepts
  // is the loader's job. Doing it here would be a second table to drift.
  expect(vless_config.find("\"fingerprint\":\"chrome\"") != std::string::npos,
         "the link's own fingerprint word is carried through");
  expect(vless_config.find("\"type\":\"vless\"") != std::string::npos, "vless is named so the engine knows which core to start");
  expect(vless_config.find("\"security\":\"reality\"") != std::string::npos, "reality is described, then refused by the core that lacks it");

  // Both engines now run the same TUN-level classifier, so the lists reach the
  // VLESS document too. Only the DNS hijack stays a hysteria2 feature: the
  // VLESS dialer sends DNS through the core.
  const auto vless_split =
      build_engine_config(vless, "203.0.113.11", {"lan.example"}, {"youtube.com"}, "direct_non_forced", 0, "");
  expect(vless_split.find("\"routing_applied\":true") != std::string::npos,
         "vless applies the site routing now");
  expect(vless_split.find("\"dns_hijack\":false") != std::string::npos,
         "vless does not claim a dns hijack");
  expect(vless_split.find("youtube.com") != std::string::npos,
         "the force-proxy list reaches the vless dialer");
  expect(vless_split.find("lan.example") != std::string::npos,
         "the exclusion list reaches the vless dialer");
  expect(vless_split.find("\"udp_mode\":\"direct_non_forced\"") != std::string::npos,
         "the udp mode reaches the vless dialer");
  // The same call for hysteria2 still claims what that engine applies.
  expect(config.find("\"routing_applied\":true") != std::string::npos,
         "hysteria2 still claims the routing it applies");

  // A WebSocket VLESS line is the shape subscriptions hand out. Dropping
  // path/host/alpn left the engine with a line it could not describe, and it
  // refused the whole line as if the transport itself were unsupported.
  ShareLine ws;
  error.clear();
  const std::string ws_uri =
      "vless://11111111-2222-3333-4444-555555555555@edge.example:443"
      "?security=tls&type=ws&path=%2Fray&host=cdn.example&alpn=h2,http%2F1.1&sni=cdn.example";
  expect(parse_share_line(ws_uri, ws, error), "parse a websocket vless line");
  expect(ws.network == "ws", "network is read");
  expect(ws.path == "/ray", "path is decoded");
  expect(ws.ws_host == "cdn.example", "host header is read");
  expect(ws.alpn == "h2,http/1.1", "the alpn list survives");
  const auto ws_config = build_engine_config(ws, "203.0.113.11", {}, {}, "proxy_all", 0, "");
  expect(ws_config.find("\"network\":\"ws\"") != std::string::npos, "transport reaches the engine");
  expect(ws_config.find("\"path\":\"/ray\"") != std::string::npos, "path reaches the engine");
  expect(ws_config.find("\"host\":\"cdn.example\"") != std::string::npos, "host reaches the engine");
  expect(ws_config.find("\"alpn\":\"h2,http/1.1\"") != std::string::npos, "alpn reaches the engine");

  // A line that says nothing means tcp over tls, and the two sides of the
  // process boundary have to agree on that or they describe one link two ways.
  ShareLine bare;
  error.clear();
  expect(parse_share_line("vless://11111111-2222-3333-4444-555555555555@edge.example:443", bare, error),
         "parse a bare vless line");
  expect(bare.network == "tcp", "a bare vless line is tcp");
  expect(bare.security == "tls", "a bare vless line is tls");
  const auto bare_config = build_engine_config(bare, "203.0.113.11", {}, {}, "proxy_all", 0, "");
  expect(bare_config.find("\"network\":\"tcp\"") != std::string::npos, "the default transport is written out");
  expect(bare_config.find("\"security\":\"tls\"") != std::string::npos, "the default security is written out");
  // A link that does not ask for a fingerprint gets the core's own TLS, exactly
  // as the Dart builder leaves it. Inventing "chrome" here made the same link
  // describe a different ClientHello on Windows than on Android.
  expect(bare_config.find("fingerprint") == std::string::npos,
         "no fingerprint is invented for a link that asked for none");
  expect(ws_config.find("fingerprint") == std::string::npos,
         "a websocket link without fp invents none either");

  // `peer` is the older spelling of the same field and is still what plenty of
  // providers emit. The Dart builder reads it; reading only `sni` here meant one
  // link dialled with a different server name on Windows than on Android, and
  // the side that guessed wrong failed the certificate check as a generic core
  // exit with nothing naming the cause.
  ShareLine peer;
  error.clear();
  expect(parse_share_line(
             "vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?security=tls&peer=front.example",
             peer, error),
         "parse a line that names its sni with peer");
  expect(peer.sni == "front.example", "peer is read as the server name");
  expect(peer.host == "1.2.3.4", "peer does not replace the address we dial");
  const auto peer_config = build_engine_config(peer, "203.0.113.11", {}, {}, "proxy_all", 0, "");
  expect(peer_config.find("\"sni\":\"front.example\"") != std::string::npos, "peer reaches the engine as sni");
  // An explicit sni still wins over peer, and the address is still the last
  // resort, so the three do not fight.
  ShareLine both;
  error.clear();
  expect(parse_share_line(
             "vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?sni=real.example&peer=stale.example",
             both, error),
         "parse a line with both sni and peer");
  expect(both.sni == "real.example", "sni outranks peer");

  // TCP obfuscation has no representation in the engine: the loader builds no
  // tcpSettings at all. A headerType we ignored would dial plain TCP at a server
  // expecting obfuscation and surface a generic failure.
  ShareLine obfuscated;
  error.clear();
  expect(!parse_share_line(
             "vless://11111111-2222-3333-4444-555555555555@edge.example:443?security=tls&headerType=http",
             obfuscated, error),
         "a line needing tcp obfuscation is refused");
  expect(error == "transport", "tcp obfuscation is a transport we do not carry");
  ShareLine plain;
  error.clear();
  expect(parse_share_line(
             "vless://11111111-2222-3333-4444-555555555555@edge.example:443?security=tls&headerType=none",
             plain, error),
         "headerType=none means no obfuscation and passes");

  // kcp obfuscation is a seed the loader already carries. Dropping it here left
  // the engine dialling a server that was expecting obfuscation.
  ShareLine kcp;
  error.clear();
  expect(parse_share_line(
             "vless://11111111-2222-3333-4444-555555555555@edge.example:443?security=tls&type=kcp&seed=obfuscate-me",
             kcp, error),
         "parse a kcp vless line");
  expect(kcp.kcp_seed == "obfuscate-me", "the kcp seed is read");
  const auto kcp_config = build_engine_config(kcp, "203.0.113.11", {}, {}, "proxy_all", 0, "");
  expect(kcp_config.find("\"kcp_seed\":\"obfuscate-me\"") != std::string::npos, "the kcp seed reaches the engine");

  // A line with no protocol in it is malformed, which is not the same complaint
  // as a protocol we do not carry. Blaming the protocol would send the person
  // looking for the wrong thing.
  ShareLine malformed;
  error.clear();
  expect(!parse_share_line("just-some-text", malformed, error), "a line with no scheme is refused");
  expect(error == "profile", "a malformed line is not a scheme complaint");
  ShareLine parked;
  error.clear();
  expect(!parse_share_line("trojan://pass@host:443", parked, error), "trojan is refused");
  expect(error == "scheme", "a parked protocol is named as a scheme complaint");

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
