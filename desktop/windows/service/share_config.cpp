#include "protocol.h"

#include <iostream>
#include <string>
#include <vector>

// Print the engine config the broker would hand to proxydom-engine for one share
// line, so the two halves of the Windows path can be exercised against each
// other by hand: the parser and config writer are C++, the process that consumes
// the document is Go, and until this existed nothing ran one into the other
// outside the owner's machine.
//
// Read-only and portable: no Win32, no routes, no adapter. Exit 0 with the JSON
// on stdout, 1 when the line is refused (the refusal goes to stderr under the
// same name the broker turns into a caption), 2 on a usage error.
//
//   share_config probe <server_ip> <listen_port> <uri>
//   share_config full  <server_ip> <api_port>    <uri>
//
// `probe` is not what the broker runs. It starts the engine with probe:true, so
// there is no TUN and no adapter, and that is exactly what makes the C++ -> engine
// seam testable without elevation. The broker proves the node answers with the
// egress canary instead, on the full session document (`full` below); see
// docs/ops/engine-migration/08-windows-vless-dial.md.
int main(int argc, char** argv) {
  if (argc != 5) {
    std::cerr << "usage: share_config <probe|full> <server_ip> <port> <uri>\n";
    return 2;
  }
  const std::string mode = argv[1];
  const std::string server_ip = argv[2];
  const std::string port_text = argv[3];
  const std::string uri = argv[4];

  int port = 0;
  try {
    port = std::stoi(port_text);
  } catch (...) {
    std::cerr << "port is not a number\n";
    return 2;
  }
  if (port <= 0 || port > 65535) {
    std::cerr << "port out of range\n";
    return 2;
  }

  ShareLine line;
  std::string error;
  if (!parse_share_line(uri, line, error)) {
    // The broker maps these words to captions, so print the word itself rather
    // than a sentence that would only look like one.
    std::cerr << error << "\n";
    return 1;
  }

  std::string config;
  if (mode == "probe") {
    config = build_engine_probe_config(line, server_ip, static_cast<unsigned short>(port));
  } else if (mode == "full") {
    config = build_engine_config(line, server_ip, std::vector<std::string>(),
                                 std::vector<std::string>(), false,
                                 static_cast<unsigned short>(port), "");
  } else {
    std::cerr << "unknown mode\n";
    return 2;
  }
  if (config.empty()) {
    // engine_outbound refuses an empty or IPv6 server address. Saying so is the
    // difference between "the node was not pinned" and "the line was refused".
    std::cerr << "no config for that server address\n";
    return 1;
  }
  std::cout << config << "\n";
  return 0;
}
