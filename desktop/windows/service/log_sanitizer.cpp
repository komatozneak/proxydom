#include "log_sanitizer.h"

#include <cctype>

namespace {

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

std::string sanitize_engine_output(const std::string& text) {
  std::string out = text.size() > 4096 ? text.substr(text.size() - 4096) : text;
  redact_quoted_key(out, "obfs-password");
  redact_quoted_key(out, "password");
  redact_quoted_key(out, "auth");
  redact_userinfo(out);
  for (char& ch : out) {
    if (ch == '\r' || ch == '\n') ch = ' ';
  }
  if (out.size() > 256) out.resize(256);
  return out;
}

bool engine_reported_auth_failure(const std::string& text) {
  const std::string lower = lower_copy(text);
  return lower.find("authentication failed") != std::string::npos ||
         lower.find("invalid password") != std::string::npos ||
         lower.find("auth failure") != std::string::npos;
}
