#pragma once

#include "session_supervisor.h"

#include <string>

class Win32Engine : public EngineHost {
 public:
  Win32Engine(std::wstring exe, std::wstring config);
  ~Win32Engine() override;

  bool launch_suspended(unsigned long& pid) override;
  bool assign_job() override;
  bool resume() override;
  bool request_stop() override;
  bool alive() override;
  void kill() override;
  void release() override;
  void stop_owned_processes() override;
  unsigned long last_error() const override;
  const char* start_stage() const override;
  unsigned long exit_code() const override;
  std::string output_tail() const override;

 private:
  struct Impl;
  Impl* impl_;
  void drain_output() const;
};

class Win32Sleeper : public Sleeper {
 public:
  void sleep_ms(int ms) override;
};
