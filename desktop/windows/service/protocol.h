#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

// Share-line to the Windows engine config (ADR 029, amended for the
// proxydom-engine process). No Win32 types in this header.

constexpr std::uint32_t kFrameMaxBody = 65536;

// Upper bound on `direct_domains` the broker keeps. The sites screen ships 120
// default-on suffixes, so a smaller cap silently dropped most of them and the
// dropped rows (every `steam*` name, `valvesoftware.com`) stayed on the proxy.
// 512 names stay far below kFrameMaxBody and keep every preset plus headroom.
constexpr std::size_t kMaxDirectDomains = 512;

// The TUN the broker routes into. The engine opens the wintun adapter by this
// name and assigns the address with a separate netsh process only afterwards,
// so an adapter that merely exists is not usable yet: Windows reports it up
// with no unicast address and a route into it fails at once. The config and the
// readiness check both read these, so the name and the address cannot drift.
constexpr const char* kTunName = "ProxyDomTun";
constexpr const char* kTunIpv4 = "198.18.0.1";

struct ShareLine {
  std::string scheme;
  std::string host;
  std::string password;
  std::string uuid;
  std::string obfs;
  std::string obfs_password;
  std::string sni;
  std::string server_ports;
  std::string hop_interval;
  std::string flow;
  std::string security;
  std::string public_key;
  std::string short_id;
  std::string fingerprint;
  int port = 443;
  bool insecure = false;
};

struct ClientCommand {
  std::string command;
  std::string uri;
  std::string message;
  int protocol_version = 0;
  std::int64_t generation = 0;
  std::vector<std::string> direct_domains;
  // True when `direct_domains` overflowed kMaxDirectDomains. The service log
  // records it: a silently truncated list looks like a routing bug.
  bool direct_domains_truncated = false;
  // Hosts that must stay on the proxy even when UDP bypass is on. Without them
  // the UDP rule would drag a force-proxied site out through the tunnel.
  std::vector<std::string> force_proxy_domains;
  // Route UDP to the physical NIC. Game traffic is UDP to bare IPs, which no
  // domain rule can match, and the addresses change.
  bool udp_direct = false;
};

std::string encode_frame(const std::string& json);
// Pulls one frame from [buffer]. Returns false on a hard framing error.
bool take_frame(std::string& buffer, std::string& json, std::string& error);

bool parse_command(const std::string& json, ClientCommand& out, std::string& error);
bool parse_share_line(const std::string& uri, ShareLine& out, std::string& error);
bool own_adapter_name(const std::wstring& name);
bool domain_allowed(const std::string& host);

// [server_ip] is the IPv4 pinned before the adapter comes up. Empty rejects.
// Domain lists, [udp_direct], and the clash api port are recorded in the
// document. This engine build does not apply them: routing_applied and
// dns_hijack are false, and a non-zero api port is logged as not applied.
std::string build_engine_config(const ShareLine& line,
                                const std::string& server_ip,
                                const std::vector<std::string>& domains,
                                const std::vector<std::string>& force_proxy_domains,
                                bool udp_direct,
                                unsigned short api_port,
                                const std::string& api_secret);

// Loopback SOCKS only. No TUN, no routes, no DNS hijack.
std::string build_engine_probe_config(const ShareLine& line,
                                      const std::string& server_ip,
                                      unsigned short listen_port);

std::string state_event(std::int64_t generation,
                        const std::string& state,
                        const std::string* message);

// Protocol 2. An empty code or message is JSON null. cleanup_verified is explicit
// because a missing flag must not be treated as a restored network.
std::string state_event_v2(std::int64_t generation,
                           const std::string& state,
                           const std::string& code,
                           const std::string& message,
                           bool cleanup_verified);
// Gate 2 finished. Connected is still false until the controller proves ingress.
std::string tun_ready_event(std::int64_t generation);

// One HTTP 204 per service generation. Idle resets [last_proved] to 0.
inline bool prove_generation_due(std::int64_t last_proved, std::int64_t generation) {
  return generation > 0 && generation > last_proved;
}

std::string ack_event(const std::string& command,
                      bool accepted,
                      std::int64_t generation,
                      const std::string& code,
                      const std::string& message);
