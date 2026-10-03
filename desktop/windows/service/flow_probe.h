#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

// Routing counters. The engine is the only component that knows which outbound a
// connection took, so it is asked directly instead of inferred from adapter
// octets: adapter counters cannot separate "left the tunnel direct" from "left
// the tunnel inside the proxy stream", and that difference is the whole question.

// One row of the clash api /connections list, reduced to what the journal prints.
struct FlowRow {
  std::string network;  // "udp" or "tcp" as sing-box reports it
  std::string chain;    // last element of chains[]: "proxy", "direct", ...
  std::string destination;
  std::string process;  // empty when the engine cannot name the owner
  std::uint64_t upload = 0;
  std::uint64_t download = 0;
};

struct FlowSample {
  std::vector<FlowRow> rows;
};

class FlowProbe {
 public:
  virtual ~FlowProbe() = default;
  // False when the engine is not listening or the body was unreadable. The
  // counters are diagnostics only, so a failure is journalled and never fatal.
  virtual bool poll(FlowSample& out) = 0;
  virtual unsigned long last_error() const = 0;
};

// Fresh per-session secret for the loopback controller. An unguessable token is
// the only thing standing between another local process and the connection list.
std::string make_api_secret();

// Replaces spaces and control characters so a value cannot break the journal's
// key=value framing. Paths and hostnames keep their last path segment.
std::string journal_token(const std::string& value);

// Parses a clash api /connections body. Unknown fields are skipped, a truncated
// body yields whatever parsed cleanly instead of failing the whole sample.
bool parse_connections(const std::string& body, std::vector<FlowRow>& out);

// Loopback clash api client. Null off Windows; the unit test supplies its own.
std::unique_ptr<FlowProbe> make_flow_probe(unsigned short port, const std::string& secret);
