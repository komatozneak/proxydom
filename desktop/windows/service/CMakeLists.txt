cmake_minimum_required(VERSION 3.20)
project(proxydom_tunnel LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(protocol_test protocol_test.cpp protocol.cpp)

if (WIN32)
  add_executable(ProxyDomTunnelService
    service.cpp
    protocol.cpp
    cleanup.cpp
  )
  target_link_libraries(ProxyDomTunnelService PRIVATE ws2_32 iphlpapi setupapi advapi32)
  target_compile_definitions(ProxyDomTunnelService PRIVATE UNICODE _UNICODE)
  set_target_properties(ProxyDomTunnelService PROPERTIES WIN32_EXECUTABLE TRUE)
endif()
