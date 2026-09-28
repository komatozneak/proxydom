#define PROXY_DOM_CTL_LIBRARY
#include "controller.cpp"

#include <iostream>

int main() {
  const std::wstring pipe_name =
      L"\\\\.\\pipe\\ProxyDomControllerTest-" + std::to_wstring(GetCurrentProcessId());
  HANDLE server = CreateNamedPipeW(
      pipe_name.c_str(), PIPE_ACCESS_DUPLEX,
      PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT |
          PIPE_REJECT_REMOTE_CLIENTS,
      1, 8192, 8192, 0, nullptr);
  if (server == INVALID_HANDLE_VALUE) {
    std::cerr << "FAIL create\n";
    return 1;
  }

  const std::string body =
      "{\"command\":\"connect\",\"protocol_version\":3,\"uri\":\"hy2://" +
      std::string(1000, 'x') + "@example:443\"}";
  std::string received;
  std::thread peer([&] {
    const BOOL connected =
        ConnectNamedPipe(server, nullptr) ||
        GetLastError() == ERROR_PIPE_CONNECTED;
    if (!connected || !read_json(server, received)) return;
    write_json(
        server,
        "{\"event\":\"ack\",\"command\":\"connect\",\"accepted\":true,"
        "\"generation\":7,\"code\":null,\"message\":null}");
  });

  HANDLE client = CreateFileW(pipe_name.c_str(), GENERIC_READ | GENERIC_WRITE,
                              0, nullptr, OPEN_EXISTING,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
  std::string reply;
  bool ok = client != INVALID_HANDLE_VALUE;
  if (ok) {
    DWORD mode = PIPE_READMODE_MESSAGE;
    ok = SetNamedPipeHandleState(client, &mode, nullptr, nullptr) &&
         write_json(client, body) && read_json(client, reply);
    CloseHandle(client);
  }
  peer.join();
  DisconnectNamedPipe(server);
  CloseHandle(server);

  ok = ok && received == body &&
       reply.find("\"accepted\":true") != std::string::npos &&
       reply.find("\"generation\":7") != std::string::npos;
  if (!ok) {
    std::cerr << "FAIL roundtrip\n";
    return 1;
  }
  std::cout << "ok\n";
  return 0;
}
