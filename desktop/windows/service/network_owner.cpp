#include "network_owner.h"

#include "protocol.h"

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <netioapi.h>
#include <mstcpip.h>
#include <setupapi.h>
#include <devguid.h>

#include <cstring>
#include <memory>
#include <thread>
#include <vector>

#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "setupapi.lib")

namespace {

void ensure_wsa() {
  static bool ready = false;
  if (ready) return;
  WSADATA wsa{};
  if (WSAStartup(MAKEWORD(2, 2), &wsa) == 0) ready = true;
}

std::string utf8_from_wide(const wchar_t* text) {
  if (text == nullptr || text[0] == L'\0') return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) return {};
  std::string out(static_cast<std::size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, out.data(), size, nullptr, nullptr);
  return out;
}

std::wstring wide_from_utf8(const std::string& text) {
  if (text.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
  if (size <= 1) return {};
  std::wstring out(static_cast<std::size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, out.data(), size);
  return out;
}

bool ipv4_from_text(const std::string& text, IN_ADDR* addr) {
  ensure_wsa();
  return inet_pton(AF_INET, text.c_str(), addr) == 1;
}

std::string ipv4_text(const IN_ADDR& addr) {
  ensure_wsa();
  char text[INET_ADDRSTRLEN] = {};
  if (inet_ntop(AF_INET, &addr, text, sizeof(text)) == nullptr) return {};
  return text;
}

bool same_ipv4(const std::string& text, const IN_ADDR& addr) {
  IN_ADDR parsed{};
  return ipv4_from_text(text, &parsed) && parsed.S_un.S_addr == addr.S_un.S_addr;
}

bool pin_matches(const PinPlan& pin, const MIB_IPFORWARD_ROW2& row) {
  if (row.DestinationPrefix.Prefix.si_family != AF_INET) return false;
  if (row.DestinationPrefix.PrefixLength != 32) return false;
  if (!same_ipv4(pin.destination, row.DestinationPrefix.Prefix.Ipv4.sin_addr)) return false;
  if (pin.interface_luid != 0 && row.InterfaceLuid.Value != pin.interface_luid) return false;
  return true;
}

bool ignored_delete(DWORD error) {
  return error == ERROR_NOT_FOUND || error == ERROR_FILE_NOT_FOUND;
}

bool hardware_default(MIB_IPFORWARD_ROW2* out) {
  PMIB_IPFORWARD_TABLE2 table = nullptr;
  if (GetIpForwardTable2(AF_INET, &table) != NO_ERROR || table == nullptr) return false;
  bool found = false;
  ULONG best_metric = 0xfffffffful;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    const auto& row = table->Table[i];
    if (row.DestinationPrefix.Prefix.si_family != AF_INET) continue;
    if (row.DestinationPrefix.PrefixLength != 0) continue;
    MIB_IF_ROW2 iface{};
    iface.InterfaceLuid = row.InterfaceLuid;
    if (GetIfEntry2(&iface) != NO_ERROR) continue;
    if (!iface.InterfaceAndOperStatusFlags.HardwareInterface) continue;
    if (iface.OperStatus != IfOperStatusUp) continue;
    if (own_adapter_name(iface.Alias)) continue;
    if (found && row.Metric >= best_metric) continue;
    *out = row;
    best_metric = row.Metric;
    found = true;
  }
  FreeMibTable(table);
  return found;
}

}  // namespace

bool Win32RouteTable::list_defaults(std::vector<RouteView>& out) {
  out.clear();
  PMIB_IPFORWARD_TABLE2 table = nullptr;
  const auto rc = GetIpForwardTable2(AF_INET, &table);
  if (rc != NO_ERROR || table == nullptr) {
    last_error_ = rc == NO_ERROR ? ERROR_NOT_FOUND : rc;
    return false;
  }
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    const auto& row = table->Table[i];
    if (row.DestinationPrefix.Prefix.si_family != AF_INET) continue;
    const auto prefix = row.DestinationPrefix.PrefixLength;
    if (prefix != 0 && prefix != 1) continue;
    MIB_IF_ROW2 iface{};
    iface.InterfaceLuid = row.InterfaceLuid;
    if (GetIfEntry2(&iface) != NO_ERROR) continue;
    RouteView view;
    view.adapter = utf8_from_wide(iface.Alias);
    view.own = own_adapter_name(iface.Alias);
    view.hardware = iface.InterfaceAndOperStatusFlags.HardwareInterface && !view.own;
    view.up = iface.OperStatus == IfOperStatusUp;
    view.prefix_length = static_cast<int>(prefix);
    view.destination_host = ntohl(row.DestinationPrefix.Prefix.Ipv4.sin_addr.S_un.S_addr);
    view.metric = row.Metric;
    out.push_back(view);
  }
  FreeMibTable(table);
  last_error_ = 0;
  return true;
}

bool Win32RouteTable::plan_hardware_pin(const std::string& destination, PinPlan& out) {
  IN_ADDR addr{};
  if (!ipv4_from_text(destination, &addr)) {
    last_error_ = ERROR_INVALID_PARAMETER;
    return false;
  }
  MIB_IPFORWARD_ROW2 best{};
  if (!hardware_default(&best) || best.NextHop.si_family != AF_INET) {
    last_error_ = ERROR_NOT_FOUND;
    return false;
  }
  out = PinPlan{};
  out.destination = destination;
  out.interface_luid = best.InterfaceLuid.Value;
  out.interface_index = best.InterfaceIndex;
  out.physical_index = best.InterfaceIndex;
  out.next_hop = ipv4_text(best.NextHop.Ipv4.sin_addr);
  out.metric = best.Metric > 0 ? best.Metric : 1;
  if (out.next_hop.empty() || out.interface_luid == 0) {
    last_error_ = ERROR_NOT_FOUND;
    return false;
  }
  last_error_ = 0;
  return true;
}

bool Win32RouteTable::add_pin(const PinPlan& pin) {
  IN_ADDR dest{};
  IN_ADDR hop{};
  if (!ipv4_from_text(pin.destination, &dest) || !ipv4_from_text(pin.next_hop, &hop)) {
    last_error_ = ERROR_INVALID_PARAMETER;
    return false;
  }
  MIB_IPFORWARD_ROW2 row{};
  InitializeIpForwardEntry(&row);
  row.InterfaceLuid.Value = pin.interface_luid;
  row.InterfaceIndex = pin.interface_index;
  row.DestinationPrefix.Prefix.si_family = AF_INET;
  row.DestinationPrefix.Prefix.Ipv4.sin_family = AF_INET;
  row.DestinationPrefix.Prefix.Ipv4.sin_addr = dest;
  row.DestinationPrefix.PrefixLength = 32;
  row.NextHop.si_family = AF_INET;
  row.NextHop.Ipv4.sin_family = AF_INET;
  row.NextHop.Ipv4.sin_addr = hop;
  row.Metric = pin.metric == 0 ? 1 : pin.metric;
  row.Protocol = MIB_IPPROTO_NETMGMT;
  const auto created = CreateIpForwardEntry2(&row);
  if (created != NO_ERROR && created != ERROR_OBJECT_ALREADY_EXISTS) {
    last_error_ = created;
    return false;
  }
  last_error_ = 0;
  return true;
}

bool Win32RouteTable::delete_pin(const PinPlan& pin) {
  PMIB_IPFORWARD_TABLE2 table = nullptr;
  const auto rc = GetIpForwardTable2(AF_INET, &table);
  if (rc != NO_ERROR || table == nullptr) {
    last_error_ = rc == NO_ERROR ? ERROR_NOT_FOUND : rc;
    return false;
  }
  std::vector<MIB_IPFORWARD_ROW2> matches;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    if (pin_matches(pin, table->Table[i])) matches.push_back(table->Table[i]);
  }
  FreeMibTable(table);
  for (auto& row : matches) {
    const auto deleted = DeleteIpForwardEntry2(&row);
    if (deleted != NO_ERROR && !ignored_delete(deleted)) {
      last_error_ = deleted;
      return false;
    }
  }
  last_error_ = 0;
  return true;
}

bool Win32RouteTable::pin_absent(const PinPlan& pin) {
  PMIB_IPFORWARD_TABLE2 table = nullptr;
  const auto rc = GetIpForwardTable2(AF_INET, &table);
  if (rc != NO_ERROR || table == nullptr) {
    last_error_ = rc == NO_ERROR ? ERROR_NOT_FOUND : rc;
    return false;
  }
  bool found = false;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    if (pin_matches(pin, table->Table[i])) found = true;
  }
  FreeMibTable(table);
  last_error_ = 0;
  return !found;
}

bool Win32RouteTable::delete_routes_on_luid(std::uint64_t luid) {
  PMIB_IPFORWARD_TABLE2 table = nullptr;
  const auto rc = GetIpForwardTable2(AF_UNSPEC, &table);
  if (rc != NO_ERROR || table == nullptr) {
    last_error_ = rc == NO_ERROR ? ERROR_NOT_FOUND : rc;
    return false;
  }
  std::vector<MIB_IPFORWARD_ROW2> matches;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    if (table->Table[i].InterfaceLuid.Value == luid) matches.push_back(table->Table[i]);
  }
  FreeMibTable(table);
  for (auto& row : matches) {
    const auto deleted = DeleteIpForwardEntry2(&row);
    if (deleted != NO_ERROR && !ignored_delete(deleted)) {
      last_error_ = deleted;
      return false;
    }
  }
  last_error_ = 0;
  return true;
}

bool Win32RouteTable::routes_absent(std::uint64_t luid) {
  PMIB_IPFORWARD_TABLE2 table = nullptr;
  const auto rc = GetIpForwardTable2(AF_UNSPEC, &table);
  if (rc != NO_ERROR || table == nullptr) {
    last_error_ = rc == NO_ERROR ? ERROR_NOT_FOUND : rc;
    return false;
  }
  bool found = false;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    if (table->Table[i].InterfaceLuid.Value == luid) found = true;
  }
  FreeMibTable(table);
  last_error_ = 0;
  return !found;
}

bool Win32RouteTable::list_own_adapters(std::vector<OwnedAdapter>& out) {
  out.clear();
  ULONG size = 16 * 1024;
  std::vector<unsigned char> buffer(size);
  ULONG rc = GetAdaptersAddresses(AF_UNSPEC, GAA_FLAG_INCLUDE_PREFIX, nullptr,
                                  reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()), &size);
  if (rc == ERROR_BUFFER_OVERFLOW) {
    buffer.resize(size);
    rc = GetAdaptersAddresses(AF_UNSPEC, GAA_FLAG_INCLUDE_PREFIX, nullptr,
                              reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()), &size);
  }
  if (rc != NO_ERROR) {
    last_error_ = rc;
    return false;
  }
  for (auto* adapter = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()); adapter != nullptr;
       adapter = adapter->Next) {
    if (adapter->FriendlyName == nullptr || !own_adapter_name(adapter->FriendlyName)) continue;
    OwnedAdapter owned;
    owned.name = utf8_from_wide(adapter->FriendlyName);
    if (adapter->AdapterName != nullptr) owned.guid = adapter->AdapterName;
    owned.luid = adapter->Luid.Value;
    owned.if_index = adapter->IfIndex;
    owned.up = adapter->OperStatus == IfOperStatusUp;
    for (auto* ua = adapter->FirstUnicastAddress; ua != nullptr; ua = ua->Next) {
      if (ua->Address.lpSockaddr == nullptr) continue;
      if (ua->Address.lpSockaddr->sa_family != AF_INET) continue;
      const auto* sin = reinterpret_cast<const sockaddr_in*>(ua->Address.lpSockaddr);
      char text[INET_ADDRSTRLEN] = {};
      if (inet_ntop(AF_INET, &sin->sin_addr, text, sizeof(text)) == nullptr) continue;
      owned.ipv4 = text;
      break;
    }
    out.push_back(owned);
  }
  last_error_ = 0;
  return true;
}

bool Win32RouteTable::find_own_adapter(OwnedAdapter& adapter) {
  std::vector<OwnedAdapter> owned;
  if (!list_own_adapters(owned)) return false;
  for (const auto& item : owned) {
    if (tun_adapter_ready(item)) {
      adapter = item;
      return true;
    }
  }
  last_error_ = ERROR_NOT_FOUND;
  return false;
}

bool Win32RouteTable::add_on_link(int family, const OwnedAdapter& adapter, const char* destination,
                                  int prefix, OwnedRoute& route) {
  MIB_IPFORWARD_ROW2 row{};
  InitializeIpForwardEntry(&row);
  row.InterfaceLuid.Value = adapter.luid;
  row.InterfaceIndex = adapter.if_index;
  row.DestinationPrefix.PrefixLength = static_cast<UINT8>(prefix);
  row.Metric = 1;
  row.Protocol = MIB_IPPROTO_NETMGMT;
  if (family == AF_INET) {
    row.DestinationPrefix.Prefix.si_family = AF_INET;
    row.DestinationPrefix.Prefix.Ipv4.sin_family = AF_INET;
    if (inet_pton(AF_INET, destination, &row.DestinationPrefix.Prefix.Ipv4.sin_addr) != 1) {
      last_error_ = ERROR_INVALID_PARAMETER;
      return false;
    }
    row.NextHop.si_family = AF_INET;
    row.NextHop.Ipv4.sin_family = AF_INET;
  } else {
    row.DestinationPrefix.Prefix.si_family = AF_INET6;
    row.DestinationPrefix.Prefix.Ipv6.sin6_family = AF_INET6;
    if (inet_pton(AF_INET6, destination, &row.DestinationPrefix.Prefix.Ipv6.sin6_addr) != 1) {
      last_error_ = ERROR_INVALID_PARAMETER;
      return false;
    }
    row.NextHop.si_family = AF_INET6;
    row.NextHop.Ipv6.sin6_family = AF_INET6;
  }
  const auto created = CreateIpForwardEntry2(&row);
  if (created != NO_ERROR && created != ERROR_OBJECT_ALREADY_EXISTS) {
    last_error_ = created;
    return false;
  }
  route.destination = destination;
  route.prefix_length = prefix;
  route.interface_luid = adapter.luid;
  route.interface_index = adapter.if_index;
  last_error_ = 0;
  return true;
}

bool Win32RouteTable::add_canary(const OwnedAdapter& adapter, const std::string& ip, OwnedRoute& route) {
  if (adapter.luid == 0 || adapter.if_index == 0 || ip.empty()) {
    last_error_ = ERROR_INVALID_PARAMETER;
    return false;
  }
  return add_on_link(AF_INET, adapter, ip.c_str(), 32, route);
}

bool Win32RouteTable::delete_canary(const OwnedRoute& route) {
  if (route.interface_luid == 0 || route.prefix_length != 32) {
    last_error_ = ERROR_INVALID_PARAMETER;
    return false;
  }
  IN_ADDR want{};
  if (inet_pton(AF_INET, route.destination.c_str(), &want) != 1) {
    last_error_ = ERROR_INVALID_PARAMETER;
    return false;
  }
  PMIB_IPFORWARD_TABLE2 table = nullptr;
  const auto rc = GetIpForwardTable2(AF_INET, &table);
  if (rc != NO_ERROR || table == nullptr) {
    last_error_ = rc == NO_ERROR ? ERROR_NOT_FOUND : rc;
    return false;
  }
  bool ok = true;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    const auto& row = table->Table[i];
    if (row.InterfaceLuid.Value != route.interface_luid) continue;
    if (row.DestinationPrefix.Prefix.si_family != AF_INET) continue;
    if (row.DestinationPrefix.PrefixLength != 32) continue;
    if (row.DestinationPrefix.Prefix.Ipv4.sin_addr.S_un.S_addr != want.S_un.S_addr) continue;
    auto copy = row;
    const auto deleted = DeleteIpForwardEntry2(&copy);
    if (deleted != NO_ERROR && deleted != ERROR_NOT_FOUND) {
      last_error_ = deleted;
      ok = false;
      break;
    }
  }
  FreeMibTable(table);
  if (ok) last_error_ = 0;
  return ok;
}

bool Win32RouteTable::fetch_canary(const std::string& ip, const std::function<bool()>& cancelled) {
  ensure_wsa();
  IN_ADDR addr{};
  if (inet_pton(AF_INET, ip.c_str(), &addr) != 1) {
    last_error_ = ERROR_INVALID_PARAMETER;
    return false;
  }
  SOCKET sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (sock == INVALID_SOCKET) {
    last_error_ = WSAGetLastError();
    return false;
  }
  u_long nb = 1;
  ioctlsocket(sock, FIONBIO, &nb);
  sockaddr_in dest{};
  dest.sin_family = AF_INET;
  dest.sin_port = htons(80);
  dest.sin_addr = addr;
  const ULONGLONG deadline = GetTickCount64() + 3500;
  const int rc = connect(sock, reinterpret_cast<sockaddr*>(&dest), sizeof(dest));
  if (rc != 0 && WSAGetLastError() != WSAEWOULDBLOCK) {
    last_error_ = WSAGetLastError();
    closesocket(sock);
    return false;
  }
  if (rc != 0) {
    fd_set wr;
    fd_set ex;
    FD_ZERO(&wr);
    FD_ZERO(&ex);
    FD_SET(sock, &wr);
    FD_SET(sock, &ex);
    const ULONGLONG now = GetTickCount64();
    const DWORD left = now >= deadline ? 0 : static_cast<DWORD>(deadline - now);
    timeval tv{};
    tv.tv_sec = static_cast<long>(left / 1000);
    tv.tv_usec = static_cast<long>((left % 1000) * 1000);
    if (select(0, nullptr, &wr, &ex, &tv) <= 0) {
      last_error_ = ERROR_TIMEOUT;
      closesocket(sock);
      return false;
    }
    int so_error = 0;
    int so_len = sizeof(so_error);
    getsockopt(sock, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&so_error), &so_len);
    if (so_error != 0) {
      last_error_ = static_cast<unsigned long>(so_error);
      closesocket(sock);
      return false;
    }
  }
  u_long block = 0;
  ioctlsocket(sock, FIONBIO, &block);
  const ULONGLONG now = GetTickCount64();
  DWORD timeout = now >= deadline ? 1 : static_cast<DWORD>(deadline - now);
  if (timeout < 1) timeout = 1;
  setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));
  setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));
  const char* request =
      "GET /generate_204 HTTP/1.1\r\nHost: cp.cloudflare.com\r\nConnection: close\r\n\r\n";
  if (send(sock, request, static_cast<int>(std::strlen(request)), 0) <= 0) {
    last_error_ = WSAGetLastError();
    closesocket(sock);
    return false;
  }
  std::string response;
  char buf[512];
  for (;;) {
    if (cancelled && cancelled()) {
      closesocket(sock);
      return false;
    }
    if (GetTickCount64() >= deadline) {
      last_error_ = ERROR_TIMEOUT;
      closesocket(sock);
      return false;
    }
    const int got = recv(sock, buf, sizeof(buf), 0);
    if (got < 0) {
      last_error_ = WSAGetLastError();
      closesocket(sock);
      return false;
    }
    if (got == 0) break;
    response.append(buf, got);
    if (response.find(" 204") != std::string::npos) {
      closesocket(sock);
      last_error_ = 0;
      return true;
    }
    if (response.size() > 8192) break;
  }
  closesocket(sock);
  last_error_ = ERROR_INVALID_DATA;
  return false;
}

bool Win32RouteTable::install_capture(const OwnedAdapter& adapter, std::vector<OwnedRoute>& routes) {
  ensure_wsa();
  routes.clear();
  if (adapter.luid == 0 || adapter.if_index == 0) {
    last_error_ = ERROR_INVALID_PARAMETER;
    return false;
  }
  const char* destinations[] = {"0.0.0.0", "128.0.0.0", "::", "8000::"};
  const int families[] = {AF_INET, AF_INET, AF_INET6, AF_INET6};
  for (int i = 0; i < 4; ++i) {
    OwnedRoute route;
    if (!add_on_link(families[i], adapter, destinations[i], 1, route)) return false;
    routes.push_back(route);
  }
  return true;
}

bool Win32RouteTable::remove_adapter(const OwnedAdapter& adapter) {
  const std::wstring guid = wide_from_utf8(adapter.guid);
  if (guid.empty()) {
    last_error_ = ERROR_INVALID_PARAMETER;
    return false;
  }
  HDEVINFO info = SetupDiGetClassDevsW(&GUID_DEVCLASS_NET, nullptr, nullptr, DIGCF_PRESENT);
  if (info == INVALID_HANDLE_VALUE) {
    last_error_ = GetLastError();
    return false;
  }
  bool removed = false;
  SP_DEVINFO_DATA data{};
  data.cbSize = sizeof(data);
  for (DWORD index = 0; SetupDiEnumDeviceInfo(info, index, &data); ++index) {
    HKEY key = SetupDiOpenDevRegKey(info, &data, DICS_FLAG_GLOBAL, 0, DIREG_DRV, KEY_READ);
    if (key == INVALID_HANDLE_VALUE) continue;
    wchar_t id[128] = {};
    DWORD bytes = sizeof(id);
    DWORD type = 0;
    const bool match = RegQueryValueExW(key, L"NetCfgInstanceId", nullptr, &type,
                                         reinterpret_cast<LPBYTE>(id), &bytes) == ERROR_SUCCESS &&
                       _wcsicmp(id, guid.c_str()) == 0;
    RegCloseKey(key);
    if (!match) continue;
    SP_REMOVEDEVICE_PARAMS params{};
    params.ClassInstallHeader.cbSize = sizeof(SP_CLASSINSTALL_HEADER);
    params.ClassInstallHeader.InstallFunction = DIF_REMOVE;
    params.Scope = DI_REMOVEDEVICE_GLOBAL;
    params.HwProfile = 0;
    if (!SetupDiSetClassInstallParamsW(info, &data, &params.ClassInstallHeader, sizeof(params))) {
      last_error_ = GetLastError();
      SetupDiDestroyDeviceInfoList(info);
      return false;
    }
    if (!SetupDiCallClassInstaller(DIF_REMOVE, info, &data)) {
      last_error_ = GetLastError();
      SetupDiDestroyDeviceInfoList(info);
      return false;
    }
    removed = true;
    break;
  }
  SetupDiDestroyDeviceInfoList(info);
  if (!removed) {
    last_error_ = ERROR_NOT_FOUND;
    return false;
  }
  last_error_ = 0;
  return true;
}

bool Win32RouteTable::tun_ready(OwnedAdapter& adapter, std::vector<OwnedRoute>& halves) {
  halves.clear();
  std::vector<OwnedAdapter> owned;
  if (!list_own_adapters(owned)) return false;
  const OwnedAdapter* tun = nullptr;
  for (const auto& item : owned) {
    if (item.name == "ProxyDomTun" && item.up && item.if_index != 0) tun = &item;
  }
  if (tun == nullptr) return false;
  PMIB_IPFORWARD_TABLE2 table = nullptr;
  if (GetIpForwardTable2(AF_INET, &table) != NO_ERROR || table == nullptr) {
    last_error_ = GetLastError();
    return false;
  }
  bool half_low = false;
  bool half_high = false;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    const auto& row = table->Table[i];
    if (row.InterfaceLuid.Value != tun->luid) continue;
    if (row.DestinationPrefix.Prefix.si_family != AF_INET) continue;
    if (row.DestinationPrefix.PrefixLength != 1) continue;
    const auto raw = ntohl(row.DestinationPrefix.Prefix.Ipv4.sin_addr.S_un.S_addr);
    OwnedRoute route;
    route.prefix_length = 1;
    route.interface_luid = tun->luid;
    route.interface_index = tun->if_index;
    if (raw == 0) {
      half_low = true;
      route.destination = "0.0.0.0";
      halves.push_back(route);
    }
    if (raw == 0x80000000u) {
      half_high = true;
      route.destination = "128.0.0.0";
      halves.push_back(route);
    }
  }
  FreeMibTable(table);
  if (!(half_low && half_high)) return false;
  adapter = *tun;
  last_error_ = 0;
  return true;
}

bool Win32RouteTable::prove_exit(unsigned long if_index,
                                const std::string& probe_ip,
                                const std::function<bool()>& cancelled) {
  ensure_wsa();
  IN_ADDR addr{};
  if (inet_pton(AF_INET, probe_ip.c_str(), &addr) != 1) {
    last_error_ = ERROR_INVALID_PARAMETER;
    return false;
  }
  SOCKET sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (sock == INVALID_SOCKET) {
    last_error_ = WSAGetLastError();
    return false;
  }
  u_long nb = 1;
  ioctlsocket(sock, FIONBIO, &nb);
  const DWORD bound = htonl(if_index);
  setsockopt(sock, IPPROTO_IP, IP_UNICAST_IF, reinterpret_cast<const char*>(&bound), sizeof(bound));
  sockaddr_in dest{};
  dest.sin_family = AF_INET;
  dest.sin_port = htons(80);
  dest.sin_addr = addr;
  const int rc = connect(sock, reinterpret_cast<sockaddr*>(&dest), sizeof(dest));
  if (rc != 0 && WSAGetLastError() != WSAEWOULDBLOCK) {
    last_error_ = WSAGetLastError();
    closesocket(sock);
    return false;
  }
  bool writable = false;
  for (int i = 0; i < 35; ++i) {
    if (cancelled && cancelled()) {
      closesocket(sock);
      return false;
    }
    fd_set write_set;
    FD_ZERO(&write_set);
    FD_SET(sock, &write_set);
    timeval tv{};
    tv.tv_usec = 200000;
    if (select(0, nullptr, &write_set, nullptr, &tv) > 0) {
      writable = true;
      break;
    }
  }
  if (!writable) {
    last_error_ = ERROR_TIMEOUT;
    closesocket(sock);
    return false;
  }
  const char* request =
      "GET /generate_204 HTTP/1.1\r\nHost: cp.cloudflare.com\r\nConnection: close\r\n\r\n";
  send(sock, request, static_cast<int>(strlen(request)), 0);
  bool readable = false;
  for (int i = 0; i < 35; ++i) {
    if (cancelled && cancelled()) {
      closesocket(sock);
      return false;
    }
    fd_set read_set;
    FD_ZERO(&read_set);
    FD_SET(sock, &read_set);
    timeval tv{};
    tv.tv_usec = 200000;
    if (select(0, &read_set, nullptr, nullptr, &tv) > 0) {
      readable = true;
      break;
    }
  }
  if (!readable) {
    last_error_ = ERROR_TIMEOUT;
    closesocket(sock);
    return false;
  }
  char buf[512] = {};
  const int got = recv(sock, buf, sizeof(buf) - 1, 0);
  closesocket(sock);
  if (got <= 0) {
    last_error_ = WSAGetLastError();
    return false;
  }
  const bool ok = std::string(buf, got).find("204") != std::string::npos;
  last_error_ = ok ? 0 : ERROR_INVALID_DATA;
  return ok;
}

struct ResolveJob {
  std::string host;
  std::string ip;
  bool ok = false;
  HANDLE done = nullptr;

  ~ResolveJob() {
    if (done != nullptr) CloseHandle(done);
  }
};

void resolve_worker(const std::shared_ptr<ResolveJob>& job) {
  ADDRINFOA hints{};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  ADDRINFOA* result = nullptr;
  if (getaddrinfo(job->host.c_str(), nullptr, &hints, &result) == 0 && result != nullptr) {
    char text[INET_ADDRSTRLEN] = {};
    const auto* addr = reinterpret_cast<sockaddr_in*>(result->ai_addr);
    if (inet_ntop(AF_INET, &addr->sin_addr, text, sizeof(text)) != nullptr) {
      job->ip = text;
      job->ok = !job->ip.empty();
    }
    freeaddrinfo(result);
  }
  if (job->done != nullptr) SetEvent(job->done);
}

bool Win32Resolver::resolve_ipv4(const std::string& host, std::string& ip) {
  ensure_wsa();
  if (host.empty()) return false;
  auto job = std::make_shared<ResolveJob>();
  job->host = host;
  job->done = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (job->done == nullptr) return false;
  // getaddrinfo has no cancel. The worker keeps the job alive after this wait.
  std::thread(resolve_worker, job).detach();
  if (WaitForSingleObject(job->done, 8000) != WAIT_OBJECT_0) return false;
  if (!job->ok) return false;
  ip = job->ip;
  return true;
}

bool Win32ConnectivityProbe::pick_loopback_port(unsigned short& port) {
  ensure_wsa();
  stage_ = "";
  SOCKET sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (sock == INVALID_SOCKET) {
    last_error_ = WSAGetLastError();
    stage_ = "bind_failed";
    return false;
  }
  sockaddr_in local{};
  local.sin_family = AF_INET;
  local.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  local.sin_port = 0;
  if (bind(sock, reinterpret_cast<sockaddr*>(&local), sizeof(local)) != 0) {
    last_error_ = WSAGetLastError();
    stage_ = "bind_failed";
    closesocket(sock);
    return false;
  }
  int size = sizeof(local);
  if (getsockname(sock, reinterpret_cast<sockaddr*>(&local), &size) != 0) {
    last_error_ = WSAGetLastError();
    stage_ = "bind_failed";
    closesocket(sock);
    return false;
  }
  port = ntohs(local.sin_port);
  closesocket(sock);
  if (port == 0) {
    last_error_ = ERROR_INVALID_DATA;
    stage_ = "bind_failed";
    return false;
  }
  last_error_ = 0;
  return true;
}

bool Win32ConnectivityProbe::prove_socks(
    unsigned short port,
    const std::string& target_ip,
    const std::function<bool()>& cancelled) {
  ensure_wsa();
  stage_ = "";
  last_error_ = 0;
  IN_ADDR target{};
  if (port == 0 || inet_pton(AF_INET, target_ip.c_str(), &target) != 1) {
    last_error_ = ERROR_INVALID_PARAMETER;
    stage_ = "socks_unreachable";
    return false;
  }

  const ULONGLONG deadline = GetTickCount64() + 12000;
  auto expired = [&]() { return GetTickCount64() >= deadline; };
  auto keep_error = [&](unsigned long fallback) {
    if (last_error_ == 0) last_error_ = fallback;
  };
  SOCKET sock = INVALID_SOCKET;
  while (sock == INVALID_SOCKET) {
    if (expired() || (cancelled && cancelled())) {
      keep_error(ERROR_TIMEOUT);
      stage_ = "socks_unreachable";
      return false;
    }
    SOCKET candidate = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (candidate == INVALID_SOCKET) {
      keep_error(WSAGetLastError());
      break;
    }
    u_long nonblocking = 1;
    ioctlsocket(candidate, FIONBIO, &nonblocking);
    sockaddr_in local{};
    local.sin_family = AF_INET;
    local.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    local.sin_port = htons(port);
    const int connected = connect(candidate, reinterpret_cast<sockaddr*>(&local), sizeof(local));
    if (connected != 0 && WSAGetLastError() != WSAEWOULDBLOCK) {
      last_error_ = WSAGetLastError();
      closesocket(candidate);
      Sleep(100);
      continue;
    }
    if (connected != 0) {
      fd_set ready;
      FD_ZERO(&ready);
      FD_SET(candidate, &ready);
      timeval wait{0, 250000};
      if (select(0, nullptr, &ready, nullptr, &wait) <= 0) {
        keep_error(ERROR_TIMEOUT);
        closesocket(candidate);
        Sleep(100);
        continue;
      }
      int so_error = 0;
      int so_len = sizeof(so_error);
      getsockopt(candidate, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&so_error), &so_len);
      if (so_error != 0) {
        last_error_ = static_cast<unsigned long>(so_error);
        closesocket(candidate);
        Sleep(100);
        continue;
      }
    }
    u_long blocking = 0;
    ioctlsocket(candidate, FIONBIO, &blocking);
    sock = candidate;
    last_error_ = 0;
    break;
  }
  if (sock == INVALID_SOCKET) {
    keep_error(ERROR_TIMEOUT);
    stage_ = "socks_unreachable";
    return false;
  }
  if (expired()) {
    closesocket(sock);
    keep_error(ERROR_TIMEOUT);
    stage_ = "socks_handshake";
    return false;
  }

  DWORD timeout = 5000;
  const ULONGLONG now = GetTickCount64();
  if (now < deadline && deadline - now < timeout) {
    timeout = static_cast<DWORD>(deadline - now);
    if (timeout < 1000) timeout = 1000;
  }
  setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));
  setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));
  auto send_all = [&](const unsigned char* bytes, int count) {
    int sent = 0;
    while (sent < count) {
      if (expired() || (cancelled && cancelled())) {
        keep_error(ERROR_TIMEOUT);
        return false;
      }
      const int n = send(sock, reinterpret_cast<const char*>(bytes + sent), count - sent, 0);
      if (n <= 0) {
        keep_error(WSAGetLastError());
        return false;
      }
      sent += n;
    }
    return true;
  };
  auto recv_all = [&](unsigned char* bytes, int count) {
    int got = 0;
    while (got < count) {
      if (expired() || (cancelled && cancelled())) {
        keep_error(ERROR_TIMEOUT);
        return false;
      }
      const int n = recv(sock, reinterpret_cast<char*>(bytes + got), count - got, 0);
      if (n <= 0) {
        keep_error(WSAGetLastError());
        return false;
      }
      got += n;
    }
    return true;
  };

  const unsigned char greeting[] = {5, 1, 0};
  unsigned char greeting_reply[2] = {};
  if (!send_all(greeting, sizeof(greeting)) ||
      !recv_all(greeting_reply, sizeof(greeting_reply)) ||
      greeting_reply[0] != 5 || greeting_reply[1] != 0) {
    keep_error(ERROR_ACCESS_DENIED);
    stage_ = "socks_handshake";
    closesocket(sock);
    return false;
  }

  unsigned char request[10] = {5, 1, 0, 1};
  std::memcpy(request + 4, &target.S_un.S_addr, 4);
  request[8] = 0;
  request[9] = 80;
  unsigned char reply[10] = {};
  if (!send_all(request, sizeof(request)) ||
      !recv_all(reply, sizeof(reply)) ||
      reply[0] != 5 || reply[1] != 0) {
    keep_error(ERROR_CONNECTION_REFUSED);
    stage_ = "socks_refused";
    closesocket(sock);
    return false;
  }

  const char* http =
      "GET /generate_204 HTTP/1.1\r\nHost: cp.cloudflare.com\r\nConnection: close\r\n\r\n";
  if (!send_all(reinterpret_cast<const unsigned char*>(http), static_cast<int>(std::strlen(http)))) {
    keep_error(ERROR_TIMEOUT);
    stage_ = "http_timeout";
    closesocket(sock);
    return false;
  }
  char response[1024] = {};
  const int got = recv(sock, response, sizeof(response) - 1, 0);
  closesocket(sock);
  if (got <= 0) {
    const int err = WSAGetLastError();
    if (err != 0) last_error_ = static_cast<unsigned long>(err);
    keep_error(ERROR_TIMEOUT);
    stage_ = "http_timeout";
    return false;
  }
  if (std::string(response, got).find(" 204") == std::string::npos) {
    last_error_ = ERROR_INVALID_DATA;
    stage_ = "http_bad_status";
    return false;
  }
  last_error_ = 0;
  stage_ = "";
  return true;
}
