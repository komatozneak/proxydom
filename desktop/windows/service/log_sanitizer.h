#pragma once

#include <string>

// Engine text may echo a share line. The journal keeps the failure, not the secret.
// The full form is the last 4096 characters. The short form is the first 256 of that.
std::string sanitize_engine_output_full(const std::string& text);
std::string sanitize_engine_output(const std::string& text);

// Keeps the END of the engine output instead of the beginning. The lines that
// say why a session failed are the last ones the engine printed, and the
// first-256 cut dropped exactly those behind a status banner.
std::string sanitize_engine_output_recent(const std::string& text, std::size_t keep);

// Hysteria2 does not report auth failure as HTTP 401. Only the engine text does.
bool engine_reported_auth_failure(const std::string& text);
