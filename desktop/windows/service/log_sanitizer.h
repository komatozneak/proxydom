#pragma once

#include <string>

// Engine text may echo a share line. The journal keeps the failure, not the secret.
// The full form is the last 4096 characters. The short form is the first 256 of that.
std::string sanitize_engine_output_full(const std::string& text);
std::string sanitize_engine_output(const std::string& text);

// Hysteria2 does not report auth failure as HTTP 401. Only the engine text does.
bool engine_reported_auth_failure(const std::string& text);
