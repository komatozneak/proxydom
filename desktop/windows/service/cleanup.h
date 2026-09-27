#pragma once

#include <string>

// Removes ProxyDomTun and teremokhy2, and the /32 pin recorded in pin.txt.
// Does not call WintunDeleteDriver.
void sweep_tunnel_leftovers();

// Pins [ipv4] via the current physical gateway. Records it for sweep.
bool pin_server_route(const std::string& ipv4);

// True when ProxyDomTun is up and both IPv4 halves point at it.
bool tun_routes_ready(unsigned long* if_index);

// HTTP 204 bound to [if_index]. Seven second limit.
bool prove_exit(unsigned long if_index);

// Physical interface index used to reach [ipv4] before the tun exists.
bool physical_interface_for(const std::string& ipv4, unsigned long* if_index);

std::wstring session_config_path();
bool write_session_file(const std::string& json);
void erase_session_file();
