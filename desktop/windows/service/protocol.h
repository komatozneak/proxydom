#pragma once

#include <cstdint>
#include <string>
#include <vector>

// Share-line to sing-box config for ADR 029. No Win32 types in this header.

constexpr std::uint32_t kFrameMaxBody = 65536;

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
};

std::string encode_frame(const std::string& json);
// Pulls one frame from [buffer]. Returns false on a hard framing error.
bool take_frame(std::string& buffer, std::string& json, std::string& error);

bool parse_command(const std::string& json, ClientCommand& out, std::string& error);
bool parse_share_line(const std::string& uri, ShareLine& out, std::string& error);
bool own_adapter_name(const std::wstring& name);
bool domain_allowed(const std::string& host);

// [server_ip] is the IPv4 pinned before the adapter comes up. Empty rejects.
std::string build_singbox_config(const ShareLine& line,
                                 const std::string& server_ip,
                                 const std::vector<std::string>& domains);

// First prove the key through a loopback SOCKS endpoint. This config has no
// TUN inbound, auto_route, DNS hijack, or other system-network mutation.
std::string build_singbox_probe_config(const ShareLine& line,
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
