cmake_minimum_required(VERSION 3.20)
project(proxydom_tunnel LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(protocol_test protocol_test.cpp protocol.cpp)
add_executable(supervisor_test supervisor_test.cpp session_supervisor.cpp protocol.cpp)

if (WIN32)
  add_executable(ProxyDomTunnelService
    service.cpp
    protocol.cpp
    session_supervisor.cpp
    network_owner.cpp
    process_host.cpp
    session_store.cpp
  )
  target_link_libraries(ProxyDomTunnelService PRIVATE ws2_32 iphlpapi setupapi advapi32 shell32)
  target_compile_definitions(ProxyDomTunnelService PRIVATE UNICODE _UNICODE)
  target_compile_options(ProxyDomTunnelService PRIVATE /utf-8)
  set_target_properties(ProxyDomTunnelService PROPERTIES WIN32_EXECUTABLE TRUE)

  add_executable(route_probe route_probe.cpp network_owner.cpp protocol.cpp session_supervisor.cpp)
  target_link_libraries(route_probe PRIVATE ws2_32 iphlpapi setupapi advapi32)
  target_compile_definitions(route_probe PRIVATE UNICODE _UNICODE)
  target_compile_options(route_probe PRIVATE /utf-8)
endif()

if (MSVC)
  target_compile_options(protocol_test PRIVATE /utf-8)
  target_compile_options(supervisor_test PRIVATE /utf-8)
endif()
