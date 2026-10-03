#include "flow_probe.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <memory>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wincrypt.h>
#include <winhttp.h>
#endif

namespace {

// --- minimal JSON reader -------------------------------------------------
// The clash api body is machine-written and flat, but the engine adds fields
// between releases. Parsing tolerates that instead of failing the sample, so an
// unknown key never costs us the counts we came for.

struct Cursor {
  const std::string& s;
  std::size_t i = 0;

  void skip_ws() {
    while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) ++i;
  }
  bool at(char c) {
    skip_ws();
    return i < s.size() && s[i] == c;
  }
  bool eat(char c) {
    skip_ws();
    if (i < s.size() && s[i] == c) {
      ++i;
      return true;
    }
    return false;
  }
};

void append_utf8(std::string& out, unsigned int cp) {
  if (cp < 0x80) {
    out.push_back(static_cast<char>(cp));
  } else if (cp < 0x800) {
    out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
    out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  } else {
    out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
    out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
    out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  }
}

unsigned int read_hex4(Cursor& c) {
  unsigned int value = 0;
  for (int n = 0; n < 4 && c.i < c.s.size(); ++n) {
    const char ch = c.s[c.i++];
    value <<= 4;
    if (ch >= '0' && ch <= '9') value |= static_cast<unsigned>(ch - '0');
    else if (ch >= 'a' && ch <= 'f') value |= static_cast<unsigned>(ch - 'a' + 10);
    else if (ch >= 'A' && ch <= 'F') value |= static_cast<unsigned>(ch - 'A' + 10);
  }
  return value;
}

bool read_string(Cursor& c, std::string& out) {
  if (!c.eat('"')) return false;
  out.clear();
  while (c.i < c.s.size()) {
    const char ch = c.s[c.i++];
    if (ch == '"') return true;
    if (ch != '\\') {
      out.push_back(ch);
      continue;
    }
    if (c.i >= c.s.size()) return false;
    const char esc = c.s[c.i++];
    switch (esc) {
      case 'n': out.push_back('\n'); break;
      case 't': out.push_back('\t'); break;
      case 'r': out.push_back('\r'); break;
      case 'b': out.push_back('\b'); break;
      case 'f': out.push_back('\f'); break;
      case 'u': append_utf8(out, read_hex4(c)); break;
      default: out.push_back(esc); break;
    }
  }
  return false;
}

// Integers arrive unquoted. A fractional part is not something we report, so it
// is consumed and discarded rather than treated as a parse failure.
bool read_uint(Cursor& c, std::uint64_t& out) {
  c.skip_ws();
  const std::size_t start = c.i;
  while (c.i < c.s.size() && std::isdigit(static_cast<unsigned char>(c.s[c.i]))) ++c.i;
  if (c.i == start) return false;
  out = std::strtoull(c.s.substr(start, c.i - start).c_str(), nullptr, 10);
  while (c.i < c.s.size() &&
         (c.s[c.i] == '.' || c.s[c.i] == 'e' || c.s[c.i] == 'E' || c.s[c.i] == '+' ||
          c.s[c.i] == '-' || std::isdigit(static_cast<unsigned char>(c.s[c.i])))) {
    ++c.i;
  }
  return true;
}

bool skip_value(Cursor& c);

bool skip_container(Cursor& c, char open, char close) {
  if (!c.eat(open)) return false;
  if (c.eat(close)) return true;
  // An array holds bare values, an object holds "key":value pairs. Reading only
  // the key left the cursor on the colon and every unknown member became a
  // dropped connection.
  const bool is_object = open == '{';
  for (;;) {
    if (is_object) {
      std::string key;
      if (!read_string(c, key)) return false;
      if (!c.eat(':')) return false;
    }
    if (!skip_value(c)) return false;
    if (c.eat(',')) continue;
    return c.eat(close);
  }
}

bool skip_value(Cursor& c) {
  c.skip_ws();
  if (c.i >= c.s.size()) return false;
  switch (c.s[c.i]) {
    case '{': return skip_container(c, '{', '}');
    case '[': return skip_container(c, '[', ']');
    case '"': {
      std::string ignored;
      return read_string(c, ignored);
    }
    case 't': case 'f': case 'n': {
      while (c.i < c.s.size() && std::isalpha(static_cast<unsigned char>(c.s[c.i]))) ++c.i;
      return true;
    }
    default: {
      std::uint64_t ignored = 0;
      return read_uint(c, ignored);
    }
  }
}

std::string read_path_tail(const std::string& path) {
  const std::size_t cut = path.find_last_of("\\/");
  return cut == std::string::npos ? path : path.substr(cut + 1);
}

bool read_connection(Cursor& c, FlowRow& row) {
  if (!c.eat('{')) return false;
  std::string network;
  std::string destination_ip;
  std::string destination_port;
  std::string host;
  std::string process;
  std::string chain;
  if (c.eat('}')) return false;

  for (;;) {
    std::string key;
    if (!read_string(c, key)) return false;
    if (!c.eat(':')) return false;

    if (key == "metadata") {
      if (!c.eat('{')) return false;
      if (!c.eat('}')) {
        for (;;) {
          std::string mkey;
          std::string mval;
          if (!read_string(c, mkey) || !c.eat(':')) return false;
          if (mkey == "network" || mkey == "destinationIP" || mkey == "destinationPort" ||
              mkey == "host" || mkey == "processPath") {
            if (!read_string(c, mval)) return false;
            if (mkey == "network") network = mval;
            else if (mkey == "destinationIP") destination_ip = mval;
            else if (mkey == "destinationPort") destination_port = mval;
            else if (mkey == "host") host = mval;
            else process = read_path_tail(mval);
          } else if (!skip_value(c)) {
            return false;
          }
          if (c.eat(',')) continue;
          if (!c.eat('}')) return false;
          break;
        }
      }
    } else if (key == "chains") {
      // The last element is the outbound the connection ended up on.
      if (!c.eat('[')) return false;
      while (!c.at(']')) {
        std::string hop;
        if (!read_string(c, hop)) return false;
        chain = hop;
        if (c.eat(',')) continue;
        break;
      }
      if (!c.eat(']')) return false;
    } else if (key == "upload" || key == "download") {
      std::uint64_t value = 0;
      if (!read_uint(c, value)) return false;
      if (key == "upload") row.upload = value;
      else row.download = value;
    } else if (!skip_value(c)) {
      return false;
    }

    if (c.eat(',')) continue;
    if (!c.eat('}')) return false;
    break;
  }

  if (chain.empty()) return false;
  row.network = network;
  row.chain = chain;
  row.process = process;
  const std::string& target = host.empty() ? destination_ip : host;
  row.destination = destination_port.empty() ? target : target + ":" + destination_port;
  return true;
}

}  // namespace

#ifdef _WIN32
// Not declared by <cstdlib> unless _CRT_RAND_S is set, but always exported by
// the CRT. It draws from the OS CSPRNG, which is what a controller secret needs.
extern "C" int __cdecl rand_s(unsigned int* value);
#endif

std::string make_api_secret() {
  static const char kHex[] = "0123456789abcdef";
  std::string secret;
  secret.reserve(48);
  unsigned int value = 0;
  for (int n = 0; n < 24 && secret.size() < 48; ++n) {
    // rand_s draws from the OS CSPRNG on MSVC and needs no extra import library.
    if (rand_s(&value) != 0) break;
    secret.push_back(kHex[(value >>  0) & 0x0F]);
    secret.push_back(kHex[(value >>  4) & 0x0F]);
    secret.push_back(kHex[(value >>  8) & 0x0F]);
    secret.push_back(kHex[(value >> 12) & 0x0F]);
    secret.push_back(kHex[(value >> 16) & 0x0F]);
    secret.push_back(kHex[(value >> 20) & 0x0F]);
    secret.push_back(kHex[(value >> 24) & 0x0F]);
    secret.push_back(kHex[(value >> 28) & 0x0F]);
  }
  // A controller without a real secret would answer unauthenticated callers.
  return secret.size() == 48 ? secret : std::string(48, '0');
}

std::string journal_token(const std::string& value) {
  std::string out;
  out.reserve(value.size());
  for (const char ch : value) {
    if (ch == '\n' || ch == '\r' || ch == '\t') continue;
    // The journal frames values as key=value pairs separated by spaces.
    out.push_back(ch == ' ' ? '_' : ch);
  }
  if (out.size() > 96) out.resize(96);
  return out;
}

bool parse_connections(const std::string& body, std::vector<FlowRow>& out) {
  out.clear();
  Cursor cursor{body};
  if (!cursor.eat('{')) return false;

  // Top-level members before "connections" are totals we do not need.
  for (;;) {
    std::string key;
    if (!read_string(cursor, key)) return false;
    if (!cursor.eat(':')) return false;
    if (key != "connections") {
      if (!skip_value(cursor)) return false;
      if (cursor.eat(',')) continue;
      return false;  // no connections member at all
    }
    if (!cursor.eat('[')) return false;
    while (!cursor.at(']')) {
      FlowRow row;
      if (read_connection(cursor, row)) out.push_back(row);
      if (!cursor.eat(',')) break;
    }
    cursor.eat(']');
    return true;
  }
}

#ifdef _WIN32

namespace {

class WinHttpFlowProbe : public FlowProbe {
 public:
  WinHttpFlowProbe(unsigned short port, std::string secret)
      : port_(port), secret_(std::move(secret)) {}

  bool poll(FlowSample& out) override {
    error_ = 0;
    HINTERNET session = WinHttpOpen(L"ProxyDomBroker/1", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                   WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (session == nullptr) {
      error_ = GetLastError();
      return false;
    }
    WinHttpSetTimeouts(session, 1500, 1500, 1500, 1500);

    wchar_t host[16] = L"127.0.0.1";
    std::wstring path = L"/connections";
    HINTERNET connect = WinHttpConnect(session, host, port_, 0);
    bool ok = false;
    std::string body;
    if (connect != nullptr) {
      const std::wstring headers =
          L"Authorization: Bearer " + std::wstring(secret_.begin(), secret_.end()) + L"\r\n";
      // The controller answers on loopback and never redirects. Saying so stops
      // an unexpected 30x from turning a diagnostic read into a second request.
      DWORD disable_redirects = WINHTTP_DISABLE_REDIRECTS;
      WinHttpSetOption(connect, WINHTTP_OPTION_DISABLE_FEATURE, &disable_redirects,
                       sizeof(disable_redirects));
      HINTERNET request = WinHttpOpenRequest(connect, L"GET", path.c_str(), nullptr,
                                             WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
      if (request != nullptr &&
          WinHttpSendRequest(request, headers.c_str(), static_cast<DWORD>(headers.size()),
                             WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
          WinHttpReceiveResponse(request, nullptr)) {
        DWORD status = 0;
        DWORD size = sizeof(status);
        if (WinHttpQueryHeaders(request,
                                WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, nullptr,
                                &status, &size, WINHTTP_NO_HEADER_INDEX) && status == 200) {
          DWORD available = 0;
          while (WinHttpQueryDataAvailable(request, &available) && available > 0) {
            std::string chunk(available, '\0');
            DWORD read = 0;
            if (!WinHttpReadData(request, chunk.data(), available, &read) || read == 0) break;
            chunk.resize(read);
            body += chunk;
            // A connection list is small; anything past this is a body we do not own.
            if (body.size() > (4u << 20)) break;
          }
          std::vector<FlowRow> rows;
          if (parse_connections(body, rows)) {
            out.rows = std::move(rows);
            ok = true;
          }
        } else {
          error_ = status;
        }
      }
      if (request != nullptr) WinHttpCloseHandle(request);
    }
    if (connect != nullptr) WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    if (!ok && error_ == 0) error_ = ERROR_INVALID_DATA;
    return ok;
  }

  unsigned long last_error() const override { return error_; }

 private:
  unsigned short port_;
  std::string secret_;
  unsigned long error_ = 0;
};

}  // namespace

std::unique_ptr<FlowProbe> make_flow_probe(unsigned short port, const std::string& secret) {
  return std::unique_ptr<FlowProbe>(new WinHttpFlowProbe(port, secret));
}

#else

std::unique_ptr<FlowProbe> make_flow_probe(unsigned short, const std::string&) {
  return nullptr;
}

#endif
