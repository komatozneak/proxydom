cmake_minimum_required(VERSION 3.20)
project(proxydom_tunnel LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(protocol_test protocol_test.cpp protocol.cpp)
add_executable(supervisor_test supervisor_test.cpp session_supervisor.cpp protocol.cpp log_sanitizer.cpp
               flow_probe.cpp)

# Portable, read-only. Prints the config the broker would give the engine for one
# share line, so the C++ parser and the Go process can be run against each other.
add_executable(share_config share_config.cpp protocol.cpp)

if (WIN32)
  add_executable(ProxyDomBroker
    service.cpp
    protocol.cpp
    session_supervisor.cpp
    network_owner.cpp
    process_host.cpp
    session_store.cpp
    log_sanitizer.cpp
    flow_probe.cpp
  )
  target_link_libraries(ProxyDomBroker PRIVATE ws2_32 iphlpapi setupapi advapi32 shell32 winhttp)
  target_compile_definitions(ProxyDomBroker PRIVATE UNICODE _UNICODE)
  target_compile_options(ProxyDomBroker PRIVATE /utf-8)
  set_target_properties(ProxyDomBroker PROPERTIES WIN32_EXECUTABLE TRUE)
  # Another PC has no VC redist. A dynamic CRT makes SCM report that the service failed to start.
  set_property(TARGET ProxyDomBroker PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded")

  add_executable(ProxyDomCtl controller.cpp protocol.cpp)
  target_link_libraries(ProxyDomCtl PRIVATE advapi32 ws2_32)
  target_compile_definitions(ProxyDomCtl PRIVATE UNICODE _UNICODE)
  target_compile_options(ProxyDomCtl PRIVATE /utf-8)
  set_property(TARGET ProxyDomCtl PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded")

  add_executable(controller_test controller_test.cpp protocol.cpp)
  target_link_libraries(controller_test PRIVATE advapi32 ws2_32)
  target_compile_definitions(controller_test PRIVATE UNICODE _UNICODE)
  target_compile_options(controller_test PRIVATE /utf-8)

  add_executable(route_probe route_probe.cpp network_owner.cpp protocol.cpp session_supervisor.cpp
                 log_sanitizer.cpp flow_probe.cpp)
  target_link_libraries(route_probe PRIVATE ws2_32 iphlpapi setupapi advapi32 winhttp)
  target_compile_definitions(route_probe PRIVATE UNICODE _UNICODE)
  target_compile_options(route_probe PRIVATE /utf-8)

  # flow_probe.cpp carries the winhttp client next to the portable parser.
  target_link_libraries(supervisor_test PRIVATE winhttp)
endif()

if (MSVC)
  target_compile_options(protocol_test PRIVATE /utf-8)
  target_compile_options(supervisor_test PRIVATE /utf-8)
  target_compile_options(share_config PRIVATE /utf-8)
endif()
