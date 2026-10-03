#define PROXY_DOM_CTL_LIBRARY
#include "controller.cpp"

#include <iostream>

int disconnect_stops_a_session_no_window_owns();

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
  // stderr, not stdout: a hung test must still say where it stopped.
  std::cerr << "ok roundtrip\n";
  return disconnect_stops_a_session_no_window_owns();
}

// ADR 034. The tunnel outlives the window, so a session started by a window
// that has since closed must still be stoppable. The command carries
// generation 0 on purpose: the stopping side does not know which generation
// it is stopping, and the broker skips its check for that case.
int disconnect_stops_a_session_no_window_owns() {
  const std::wstring pipe_name =
      L"\\\\.\\pipe\\ProxyDomDisconnectTest-" + std::to_wstring(GetCurrentProcessId());
  HANDLE server = CreateNamedPipeW(
      pipe_name.c_str(), PIPE_ACCESS_DUPLEX,
      PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
      1, 8192, 8192, 0, nullptr);
  if (server == INVALID_HANDLE_VALUE) {
    std::cerr << "FAIL create disconnect pipe\n";
    return 1;
  }

  std::string received;
  std::thread peer([&] {
    const BOOL connected =
        ConnectNamedPipe(server, nullptr) || GetLastError() == ERROR_PIPE_CONNECTED;
    if (!connected || !read_json(server, received)) return;
    // The broker answers a disconnect with an ack and then a state event. Both
    // arrive together, which is why the frame buffer has to survive between
    // reads.
    write_json(
        server,
        "{\"event\":\"ack\",\"command\":\"disconnect\",\"accepted\":true,"
        "\"generation\":3,\"code\":null,\"message\":null}");
    write_json(
        server,
        "{\"event\":\"state\",\"generation\":3,\"state\":\"idle\",\"code\":null,"
        "\"message\":null,\"cleanup_verified\":true}");
  });

  HANDLE client = CreateFileW(pipe_name.c_str(), GENERIC_READ | GENERIC_WRITE,
                              0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  bool ok = client != INVALID_HANDLE_VALUE;
  if (ok) {
    DWORD mode = PIPE_READMODE_BYTE;
    ok = SetNamedPipeHandleState(client, &mode, nullptr, nullptr) == TRUE;
  }
  // The verb drives the client end, which is the only orientation it ever
  // gets from open_broker in production.
  const int code = ok ? disconnect_once(client) : -1;
  if (client != INVALID_HANDLE_VALUE) CloseHandle(client);
  peer.join();
  DisconnectNamedPipe(server);
  CloseHandle(server);

  ok = ok && code == 0 &&
       received.find("\"command\":\"disconnect\"") != std::string::npos &&
       received.find("\"protocol_version\":3") != std::string::npos &&
       received.find("\"generation\":0") != std::string::npos;
  if (!ok) {
    std::cerr << "FAIL disconnect (" << code << ") sent: " << received << "\n";
    return 1;
  }
  std::cerr << "ok disconnect\n";
  return 0;
}
