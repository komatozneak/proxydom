#pragma once

#include "session_supervisor.h"

#include <string>

class Win32RouteTable : public RouteTable {
 public:
  bool list_defaults(std::vector<RouteView>& out) override;
  bool plan_hardware_pin(const std::string& destination, PinPlan& out) override;
  bool add_pin(const PinPlan& pin) override;
  bool delete_pin(const PinPlan& pin) override;
  bool pin_absent(const PinPlan& pin) override;
  bool delete_routes_on_luid(std::uint64_t luid) override;
  bool routes_absent(std::uint64_t luid) override;
  bool list_own_adapters(std::vector<OwnedAdapter>& out) override;
  bool remove_adapter(const OwnedAdapter& adapter) override;
  bool tun_ready(OwnedAdapter& adapter, std::vector<OwnedRoute>& halves) override;
  bool prove_exit(unsigned long if_index,
                  const std::string& probe_ip,
                  const std::function<bool()>& cancelled) override;
  unsigned long last_error() const override { return last_error_; }

 private:
  unsigned long last_error_ = 0;
};

class Win32Resolver : public NameResolver {
 public:
  bool resolve_ipv4(const std::string& host, std::string& ip) override;
};

class Win32ConnectivityProbe : public ConnectivityProbe {
 public:
  bool pick_loopback_port(unsigned short& port) override;
  bool prove_socks(unsigned short port,
                   const std::string& target_ip,
                   const std::function<bool()>& cancelled) override;
  unsigned long last_error() const override { return last_error_; }

 private:
  unsigned long last_error_ = 0;
};
