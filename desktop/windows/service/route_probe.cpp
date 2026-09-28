#include "network_owner.h"

#include <iostream>
#include <vector>

// Read-only. Exit 2 when another full tunnel would block Connect, 1 when an
// owned Proxy Dom adapter or dirty ledger is still present, 0 when clear.
int main() {
  Win32RouteTable routes;
  std::vector<RouteView> rows;
  if (!routes.list_defaults(rows)) {
    std::cerr << "route table unavailable\n";
    return 1;
  }
  const std::string foreign = active_foreign_tunnel(rows);
  std::vector<OwnedAdapter> owned;
  if (!routes.list_own_adapters(owned)) {
    std::cerr << "adapter list unavailable\n";
    return 1;
  }
  if (!owned.empty()) {
    std::cout << "owned " << owned.front().name << "\n";
    return 1;
  }
  if (!foreign.empty()) {
    std::cout << "foreign " << foreign << "\n";
    return 2;
  }
  std::cout << "clear\n";
  return 0;
}
