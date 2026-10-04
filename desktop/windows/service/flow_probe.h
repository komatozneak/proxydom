#pragma once

#include <cstddef>
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
  std::string id;  // connection id, stable for the life of the flow
  std::string network;  // "udp" or "tcp" as sing-box reports it
  std::string chain;    // last element of chains[]: "proxy", "direct", ...
  std::string destination;
  std::string process;  // empty when the engine cannot name the owner
  std::uint64_t upload = 0;
  std::uint64_t download = 0;
};

struct FlowSample {
  std::vector<FlowRow> rows;
  // Connections the body carried but that carried no id. They are left out of
  // `rows` because they cannot be told apart from the next poll's; the session
  // reports the count once rather than banking bytes it cannot attribute.
  std::size_t untracked = 0;
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
//
// `upload` and `download` are each connection's own cumulative counters, so a
// total has to be built from per-id deltas. A connection carrying no id cannot
// be told apart from the next poll's, so it is left out of `out` and counted in
// `untracked` when the caller wants to know: banking it would put the same
// bytes into the total once per poll.
bool parse_connections(const std::string& body, std::vector<FlowRow>& out,
                       std::size_t* untracked = nullptr);

// Loopback clash api client. Null off Windows; the unit test supplies its own.
std::unique_ptr<FlowProbe> make_flow_probe(unsigned short port, const std::string& secret);
