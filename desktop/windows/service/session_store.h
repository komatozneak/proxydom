#pragma once

#include "session_supervisor.h"

#include <string>

std::wstring proxy_dom_engine_config_path();

class Win32SessionFiles : public SessionFiles {
 public:
  int load(Ledger& ledger) override;
  bool store(const Ledger& ledger) override;
  bool clear() override;
  bool write_config(const std::string& json) override;
  bool erase_config() override;
  bool config_present() override;
  std::string legacy_pin() override;
  void clear_legacy_pin() override;
  unsigned long last_error() const override { return last_error_; }

 private:
  unsigned long last_error_ = 0;
};

class Win32TunnelLog : public TunnelLog {
 public:
  void write(std::int64_t generation,
             const std::string& event,
             const std::string& code,
             unsigned long win32) override;
};
