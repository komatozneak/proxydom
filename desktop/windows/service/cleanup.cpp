#include "cleanup.h"

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
#include <sddl.h>

#include <cstring>
#include <fstream>
#include <vector>

#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "setupapi.lib")
#pragma comment(lib, "advapi32.lib")

namespace {

std::wstring program_data() {
  wchar_t buf[MAX_PATH] = L"C:\\ProgramData";
  const DWORD n = GetEnvironmentVariableW(L"ProgramData", buf, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) return L"C:\\ProgramData";
  return buf;
}

std::wstring run_dir() {
  return program_data() + L"\\Proxy Dom\\run";
}

void ensure_run_dir() {
  const std::wstring root = program_data() + L"\\Proxy Dom";
  CreateDirectoryW(root.c_str(), nullptr);
  CreateDirectoryW(run_dir().c_str(), nullptr);
}

std::wstring pin_path() { return run_dir() + L"\\pin.txt"; }

bool ipv4_from_text(const std::string& text, IN_ADDR* addr) {
  return inet_pton(AF_INET, text.c_str(), addr) == 1;
}

void delete_host_route(const std::string& ipv4) {
  IN_ADDR addr{};
  if (!ipv4_from_text(ipv4, &addr)) return;
  PMIB_IPFORWARD_TABLE2 table = nullptr;
  if (GetIpForwardTable2(AF_INET, &table) != NO_ERROR || table == nullptr) return;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    auto& row = table->Table[i];
    if (row.DestinationPrefix.Prefix.si_family != AF_INET) continue;
    if (row.DestinationPrefix.PrefixLength != 32) continue;
    if (row.DestinationPrefix.Prefix.Ipv4.sin_addr.S_un.S_addr != addr.S_un.S_addr) continue;
    DeleteIpForwardEntry2(&row);
  }
  FreeMibTable(table);
}

std::string read_pin() {
  std::ifstream in(pin_path(), std::ios::binary);
  if (!in) return {};
  std::string text;
  std::getline(in, text);
  return text;
}

void remove_device_by_instance_id(const std::wstring& instance_guid) {
  HDEVINFO info = SetupDiGetClassDevsW(&GUID_DEVCLASS_NET, nullptr, nullptr, DIGCF_PRESENT);
  if (info == INVALID_HANDLE_VALUE) return;
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
                       _wcsicmp(id, instance_guid.c_str()) == 0;
    RegCloseKey(key);
    if (!match) continue;
    SP_REMOVEDEVICE_PARAMS params{};
    params.ClassInstallHeader.cbSize = sizeof(SP_CLASSINSTALL_HEADER);
    params.ClassInstallHeader.InstallFunction = DIF_REMOVE;
    params.Scope = DI_REMOVEDEVICE_GLOBAL;
    params.HwProfile = 0;
    SetupDiSetClassInstallParamsW(info, &data, &params.ClassInstallHeader, sizeof(params));
    SetupDiCallClassInstaller(DIF_REMOVE, info, &data);
    break;
  }
  SetupDiDestroyDeviceInfoList(info);
}

void delete_routes_on_luid(const NET_LUID& luid) {
  PMIB_IPFORWARD_TABLE2 table = nullptr;
  if (GetIpForwardTable2(AF_UNSPEC, &table) != NO_ERROR || table == nullptr) return;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    if (table->Table[i].InterfaceLuid.Value != luid.Value) continue;
    DeleteIpForwardEntry2(&table->Table[i]);
  }
  FreeMibTable(table);
}

}  // namespace

std::wstring session_config_path() { return run_dir() + L"\\current_session.json"; }

void sweep_tunnel_leftovers() {
  const std::string pin = read_pin();
  if (!pin.empty()) delete_host_route(pin);
  DeleteFileW(pin_path().c_str());

  ULONG size = 16 * 1024;
  std::vector<unsigned char> buffer(size);
  ULONG flags = GAA_FLAG_INCLUDE_PREFIX;
  ULONG rc = GetAdaptersAddresses(AF_UNSPEC, flags, nullptr,
                                  reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()), &size);
  if (rc == ERROR_BUFFER_OVERFLOW) {
    buffer.resize(size);
    rc = GetAdaptersAddresses(AF_UNSPEC, flags, nullptr,
                              reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()), &size);
  }
  if (rc != NO_ERROR) {
    erase_session_file();
    return;
  }
  for (auto* adapter = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()); adapter != nullptr;
       adapter = adapter->Next) {
    if (!own_adapter_name(adapter->FriendlyName)) continue;
    delete_routes_on_luid(adapter->Luid);
    if (adapter->AdapterName == nullptr) continue;
    const int needed = MultiByteToWideChar(CP_ACP, 0, adapter->AdapterName, -1, nullptr, 0);
    if (needed <= 0) continue;
    std::wstring guid(static_cast<std::size_t>(needed), L'\0');
    MultiByteToWideChar(CP_ACP, 0, adapter->AdapterName, -1, guid.data(), needed);
    if (!guid.empty() && guid.back() == L'\0') guid.pop_back();
    remove_device_by_instance_id(guid);
  }
  erase_session_file();
}

bool pin_server_route(const std::string& ipv4) {
  IN_ADDR addr{};
  if (!ipv4_from_text(ipv4, &addr)) return false;
  SOCKADDR_INET dest{};
  dest.si_family = AF_INET;
  dest.Ipv4.sin_family = AF_INET;
  dest.Ipv4.sin_addr = addr;
  MIB_IPFORWARD_ROW2 best{};
  SOCKADDR_INET source{};
  if (GetBestRoute2(nullptr, 0, nullptr, &dest, 0, &best, &source) != NO_ERROR) return false;
  MIB_IPFORWARD_ROW2 row = best;
  InitializeIpForwardEntry(&row);
  row.InterfaceLuid = best.InterfaceLuid;
  row.InterfaceIndex = best.InterfaceIndex;
  row.DestinationPrefix.Prefix.si_family = AF_INET;
  row.DestinationPrefix.Prefix.Ipv4.sin_family = AF_INET;
  row.DestinationPrefix.Prefix.Ipv4.sin_addr = addr;
  row.DestinationPrefix.PrefixLength = 32;
  row.NextHop = best.NextHop;
  row.Metric = best.Metric > 0 ? best.Metric : 1;
  row.Protocol = MIB_IPPROTO_NETMGMT;
  const auto created = CreateIpForwardEntry2(&row);
  if (created != NO_ERROR && created != ERROR_OBJECT_ALREADY_EXISTS) return false;
  ensure_run_dir();
  std::ofstream out(pin_path(), std::ios::binary | std::ios::trunc);
  if (!out) return false;
  out << ipv4;
  return true;
}

bool physical_interface_for(const std::string& ipv4, unsigned long* if_index) {
  IN_ADDR addr{};
  if (!ipv4_from_text(ipv4, &addr) || if_index == nullptr) return false;
  SOCKADDR_INET dest{};
  dest.si_family = AF_INET;
  dest.Ipv4.sin_family = AF_INET;
  dest.Ipv4.sin_addr = addr;
  MIB_IPFORWARD_ROW2 best{};
  SOCKADDR_INET source{};
  if (GetBestRoute2(nullptr, 0, nullptr, &dest, 0, &best, &source) != NO_ERROR) return false;
  *if_index = best.InterfaceIndex;
  return true;
}

bool tun_routes_ready(unsigned long* if_index) {
  ULONG size = 16 * 1024;
  std::vector<unsigned char> buffer(size);
  ULONG rc = GetAdaptersAddresses(AF_INET, GAA_FLAG_INCLUDE_PREFIX, nullptr,
                                  reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()), &size);
  if (rc == ERROR_BUFFER_OVERFLOW) {
    buffer.resize(size);
    rc = GetAdaptersAddresses(AF_INET, GAA_FLAG_INCLUDE_PREFIX, nullptr,
                              reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()), &size);
  }
  if (rc != NO_ERROR) return false;
  unsigned long index = 0;
  bool up = false;
  for (auto* adapter = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()); adapter != nullptr;
       adapter = adapter->Next) {
    if (!own_adapter_name(adapter->FriendlyName)) continue;
    if (wcscmp(adapter->FriendlyName, L"ProxyDomTun") != 0) continue;
    index = adapter->IfIndex;
    up = adapter->OperStatus == IfOperStatusUp;
    break;
  }
  if (!up || index == 0) return false;
  PMIB_IPFORWARD_TABLE2 table = nullptr;
  if (GetIpForwardTable2(AF_INET, &table) != NO_ERROR || table == nullptr) return false;
  bool half_low = false;
  bool half_high = false;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    const auto& row = table->Table[i];
    if (row.InterfaceIndex != index) continue;
    if (row.DestinationPrefix.Prefix.si_family != AF_INET) continue;
    if (row.DestinationPrefix.PrefixLength != 1) continue;
    const auto raw = ntohl(row.DestinationPrefix.Prefix.Ipv4.sin_addr.S_un.S_addr);
    if (raw == 0) half_low = true;
    if (raw == 0x80000000u) half_high = true;
  }
  FreeMibTable(table);
  if (!(half_low && half_high)) return false;
  if (if_index != nullptr) *if_index = index;
  return true;
}

bool prove_exit(unsigned long if_index) {
  ADDRINFOA hints{};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  ADDRINFOA* result = nullptr;
  if (getaddrinfo("cp.cloudflare.com", "80", &hints, &result) != 0 || result == nullptr) return false;
  SOCKET sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (sock == INVALID_SOCKET) {
    freeaddrinfo(result);
    return false;
  }
  u_long nb = 1;
  ioctlsocket(sock, FIONBIO, &nb);
  const DWORD bound = htonl(if_index);
  setsockopt(sock, IPPROTO_IP, IP_UNICAST_IF, reinterpret_cast<const char*>(&bound), sizeof(bound));
  const int rc = connect(sock, result->ai_addr, static_cast<int>(result->ai_addrlen));
  freeaddrinfo(result);
  if (rc != 0 && WSAGetLastError() != WSAEWOULDBLOCK) {
    closesocket(sock);
    return false;
  }
  fd_set write_set;
  FD_ZERO(&write_set);
  FD_SET(sock, &write_set);
  timeval tv{};
  tv.tv_sec = 7;
  if (select(0, nullptr, &write_set, nullptr, &tv) <= 0) {
    closesocket(sock);
    return false;
  }
  const char* request =
      "GET /generate_204 HTTP/1.1\r\nHost: cp.cloudflare.com\r\nConnection: close\r\n\r\n";
  send(sock, request, static_cast<int>(strlen(request)), 0);
  FD_ZERO(&write_set);
  FD_SET(sock, &write_set);
  tv.tv_sec = 7;
  fd_set read_set;
  FD_ZERO(&read_set);
  FD_SET(sock, &read_set);
  if (select(0, &read_set, nullptr, nullptr, &tv) <= 0) {
    closesocket(sock);
    return false;
  }
  char buf[512] = {};
  const int got = recv(sock, buf, sizeof(buf) - 1, 0);
  closesocket(sock);
  if (got <= 0) return false;
  return std::string(buf, got).find("204") != std::string::npos;
}

bool write_session_file(const std::string& json) {
  ensure_run_dir();
  PSECURITY_DESCRIPTOR sd = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(L"D:P(A;;FA;;;SY)(A;;FA;;;BA)", SDDL_REVISION_1, &sd,
                                                            nullptr)) {
    return false;
  }
  SECURITY_ATTRIBUTES sa{};
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = sd;
  sa.bInheritHandle = FALSE;
  const std::wstring path = session_config_path();
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, &sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  LocalFree(sd);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const BOOL ok = WriteFile(file, json.data(), static_cast<DWORD>(json.size()), &written, nullptr);
  CloseHandle(file);
  return ok && written == json.size();
}

void erase_session_file() {
  const std::wstring path = session_config_path();
  WIN32_FILE_ATTRIBUTE_DATA info{};
  if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &info)) return;
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file != INVALID_HANDLE_VALUE) {
    const DWORD bytes = info.nFileSizeLow;
    std::vector<char> zeros(bytes == 0 ? 1 : bytes, '\0');
    DWORD written = 0;
    WriteFile(file, zeros.data(), static_cast<DWORD>(zeros.size()), &written, nullptr);
    CloseHandle(file);
  }
  DeleteFileW(path.c_str());
}
