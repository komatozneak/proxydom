package com.teremok.connect.teremok_connect

/**
 * libXray as a local TUN→SOCKS pump for Hysteria (ADR 015).
 *
 * Hy2 owns `127.0.0.1:10808`; this JSON must not bind that port.
 */
internal fun hysteriaTun2SocksConfig(mtu: Int): String = """
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "protocol": "tun",
      "tag": "tun-in",
      "settings": { "name": "hy2tun", "mtu": $mtu },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": false }
    }
  ],
  "outbounds": [
    {
      "protocol": "socks",
      "tag": "hy2-socks",
      "settings": {
        "servers": [
          { "address": "${GvisorTun2Socks.SOCKS_HOST}", "port": ${GvisorTun2Socks.SOCKS_PORT} }
        ]
      }
    }
  ],
  "routing": { "domainStrategy": "AsIs", "rules": [] }
}
""".trimIndent()
