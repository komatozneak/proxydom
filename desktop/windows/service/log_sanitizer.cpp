#include "log_sanitizer.h"

#include <cctype>

namespace {

/// Keys whose value is a credential in every shape the engines emit.
const char* const kSecretKeys[] = {
    "obfs-password",
    "obfs_password",
    "password",
    "passwd",
    "auth",
    "hysteriaAuth",
    "token",
    "api_key",
    "apikey",
    "secret",
    "authorization",
    // Hysteria2 share links put the credential in the userinfo part, so for a
    // link without ":password" the username IS the password. Masking "user"
    // here is the difference between a label and a leaked node secret.
    "user",
    "username",
    "login",
    // VLESS / Reality credentials (parked engine, still in the tree). The
    // public key is deliberately NOT masked: it is public by construction, and
    // it is the one field that tells two mismatched configs apart.
    "uuid",
    "short_id",
};

void redact_quoted_key(std::string& text, const std::string& key) {
  const std::string token = "\"" + key + "\"";
  std::size_t at = 0;
  while ((at = text.find(token, at)) != std::string::npos) {
    std::size_t i = at + token.size();
    while (i < text.size() && std::isspace(static_cast<unsigned char>(text[i])) != 0) ++i;
    if (i >= text.size() || text[i] != ':') {
      at += token.size();
      continue;
    }
    ++i;
    while (i < text.size() && std::isspace(static_cast<unsigned char>(text[i])) != 0) ++i;
    if (i >= text.size() || text[i] != '"') {
      at = i;
      continue;
    }
    const std::size_t start = i + 1;
    std::size_t end = start;
    while (end < text.size() && text[end] != '"') {
      if (text[end] == '\\' && end + 1 < text.size()) end += 2;
      else ++end;
    }
    text.replace(start, end - start, "***");
    at = start + 3;
  }
}

/// `?obfs-password=secret&…` — the query form of the same keys.
///
/// redact_quoted_key only understands JSON. A share line pasted into a log or
/// echoed by an engine carries the secret in the query string, where it used to
/// survive untouched.
void redact_query_key(std::string& text, const std::string& key) {
  std::size_t at = 0;
  while ((at = text.find(key + "=", at)) != std::string::npos) {
    // Reject a hit that is only the tail of a longer token — `obfs-password=`
    // must not be masked twice under the `password=` search, and `hysteriaAuth=`
    // must not be caught again as `auth=`. Both are handled by their own key.
    if (at > 0) {
      const char prev = text[at - 1];
      const bool tail_of_token = std::isalnum(static_cast<unsigned char>(prev)) != 0 ||
                                 prev == '_' || prev == '-' || prev == '.';
      if (tail_of_token) {
        at += key.size() + 1;
        continue;
      }
    }
    const std::size_t value_start = at + key.size() + 1;
    std::size_t end = text.find_first_of(" \t\r\n&\"'", value_start);
    if (end == std::string::npos) end = text.size();
    if (end > value_start) text.replace(value_start, end - value_start, "***");
    // Resume after what is now the literal `***`. Using `end` would be stale:
    // the replacement shortened the string.
    at = value_start + 3;
  }
}

void redact_userinfo(std::string& text) {
  std::size_t scheme = 0;
  while ((scheme = text.find("://", scheme)) != std::string::npos) {
    const std::size_t start = scheme + 3;
    std::size_t end = text.find_first_of("/ \t\r\n", start);
    if (end == std::string::npos) end = text.size();
    const std::size_t at = text.find('@', start);
    if (at != std::string::npos && at < end) text.replace(start, at - start, "***");
    scheme = start + 1;
  }
}

std::string lower_copy(std::string text) {
  for (char& ch : text) ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
  return text;
}

}  // namespace

std::string sanitize_engine_output_full(const std::string& text) {
  // Redact BEFORE the window cut. Truncating first can slice `"password":"` in
  // half, and the half that survives no longer looks like a key, so the secret
  // reaches the journal in the clear. One pass over the input is cheaper than
  // a leaked credential, and the callers already chunk their input.
  std::string out = text;
  for (const char* key : kSecretKeys) {
    redact_quoted_key(out, key);
    redact_query_key(out, key);
  }
  redact_userinfo(out);
  for (char& ch : out) {
    if (ch == '\r' || ch == '\n') ch = ' ';
  }
  if (out.size() > 4096) out = out.substr(out.size() - 4096);
  return out;
}

std::string sanitize_engine_output(const std::string& text) {
  std::string out = sanitize_engine_output_full(text);
  // One service.log line is 512 bytes. Callers that write a single line stay inside it.
  if (out.size() > 256) out.resize(256);
  return out;
}

std::string sanitize_engine_output_recent(const std::string& text, std::size_t keep) {
  std::string out = sanitize_engine_output_full(text);
  if (keep == 0) keep = 256;
  if (out.size() > keep) out = out.substr(out.size() - keep);
  return out;
}

bool engine_reported_auth_failure(const std::string& text) {
  const std::string lower = lower_copy(text);
  return lower.find("authentication failed") != std::string::npos ||
         lower.find("invalid password") != std::string::npos ||
         lower.find("auth failure") != std::string::npos;
}