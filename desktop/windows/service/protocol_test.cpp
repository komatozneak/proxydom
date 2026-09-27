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
  const std::string hello = "{\"command\":\"hello\",\"protocol_version\":1}";
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
  std::string bad = std::string("\x01\x10\x00\x00", 4);
  error.clear();
  expect(!take_frame(bad, json, error) && error == "frame", "reject oversize length");

  ClientCommand command;
  error.clear();
  expect(parse_command(hello, command, error), "parse hello");
  expect(command.command == "hello" && command.protocol_version == 1, "hello fields");

  error.clear();
  expect(!parse_command("{\"command\":\"connect\",\"outbounds\":[]}", command, error), "reject outbounds");

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
  expect(line.server_ports == "1000-2000", "hop ports");
  expect(line.hop_interval == "30s", "hop interval");

  const auto config = build_singbox_config(line, "203.0.113.10", {"lan.example"});
  expect(config.find("\"route_address\":[\"0.0.0.0/1\",\"128.0.0.0/1\"]") != std::string::npos, "v4 routes");
  expect(config.find("::/0") == std::string::npos, "no v6 default");
  expect(config.find("198.18.0.1/30") != std::string::npos, "tun prefix");
  expect(config.find("198.18.0.2") != std::string::npos, "dns address");
  expect(config.find("salamander") != std::string::npos, "obfs in config");
  expect(config.find("lan.example") != std::string::npos, "direct domain");
  expect(config.find("secret+pass") != std::string::npos, "password reaches the engine config");
  expect(config.find("172.19.0.1") == std::string::npos, "tun prefix stays outside 172.16/12");
  expect(build_singbox_config(line, "2001:db8::1", {}).empty(), "refuse ipv6 pin");

  ShareLine vless;
  error.clear();
  const std::string vless_uri =
      "vless://11111111-2222-3333-4444-555555555555@edge.example:443?security=reality&pbk=pub&sid=abcd&sni=edge.example&flow=xtls-rprx-vision&fp=chrome";
  expect(parse_share_line(vless_uri, vless, error), "parse vless");
  const auto vless_config = build_singbox_config(vless, "203.0.113.11", {});
  expect(vless_config.find("\"public_key\":\"pub\"") != std::string::npos, "reality public key");
  expect(vless_config.find("private_key") == std::string::npos, "no server private key");
  expect(vless_config.find("xtls-rprx-vision") != std::string::npos, "flow");

  expect(own_adapter_name(L"ProxyDomTun"), "own tun");
  expect(own_adapter_name(L"teremokhy2"), "legacy tun");
  expect(!own_adapter_name(L"WireGuard"), "foreign tun");
  expect(domain_allowed("lan.example"), "domain");
  expect(!domain_allowed("http://lan.example"), "domain rejects a url");
  expect(!domain_allowed("../x"), "domain rejects dots");

  if (g_failed != 0) {
    std::cerr << g_failed << " failed\n";
    return 1;
  }
  std::cout << "ok\n";
  return 0;
}
