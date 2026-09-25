package hy2bind

import "github.com/xjasonlyu/tun2socks/v2/tunnel/statistic"

// TunDownlinkBytes is payload the tunnel copied from the proxy to apps.
// gomobile name: tunDownlinkBytes. UI downlink uses this, not /proc/net/dev.
func TunDownlinkBytes() int64 {
	return statistic.DefaultManager.Snapshot().DownloadTotal
}

// TunUplinkBytes is payload the tunnel copied from apps to the proxy.
// gomobile name: tunUplinkBytes.
func TunUplinkBytes() int64 {
	return statistic.DefaultManager.Snapshot().UploadTotal
}
