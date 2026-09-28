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
    out.push_back(owned);
  }
  last_error_ = 0;
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

bool Win32Resolver::resolve_ipv4(const std::string& host, std::string& ip) {
  ensure_wsa();
  ADDRINFOA hints{};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  ADDRINFOA* result = nullptr;
  if (getaddrinfo(host.c_str(), nullptr, &hints, &result) != 0 || result == nullptr) return false;
  char text[INET_ADDRSTRLEN] = {};
  const auto* addr = reinterpret_cast<sockaddr_in*>(result->ai_addr);
  const bool ok = inet_ntop(AF_INET, &addr->sin_addr, text, sizeof(text)) != nullptr;
  freeaddrinfo(result);
  if (!ok) return false;
  ip = text;
  return !ip.empty();
}
