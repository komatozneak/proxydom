/// The Imported-Document Dial Set.
///
/// Two dial sets exist and must not be confused:
///
/// * **Catalog Dial Set** — the nodes the catalog and the bot serve. Those are
///   Hysteria2 only and are not decided here.
/// * **Imported-Document Dial Set** — lines the person pasted, or pulled from a
///   foreign HTTPS document. This file is the single authority for what may
///   start there, per platform.
///
/// The parser stays wider than this set: a key this build cannot carry is still
/// read, still counted, and still kept in the document; it simply cannot start.
/// Admitted here are Hysteria2 on every OS and the five the in-process
/// `v2fly/v2ray-core` (MIT) outbound builder can describe — VLESS, VMess,
/// Trojan, Shadowsocks and SOCKS5 — on the platforms where that core runs.
/// REALITY is a security layer over VLESS and has its own permissive engine,
/// so [canDialLinkOn] admits a VLESS line whose REALITY handshake the engine
/// can describe. XHTTP is still refused: neither engine carries its framing.
/// [kParkedSchemes] names the rest by protocol.
library;

import 'package:flutter/foundation.dart';

import 'engine_share_config.dart';
import 'share_link_parser.dart';

/// The OS whose dial capability is being asked about.
///
/// Resolved from [defaultTargetPlatform] so widget tests can steer it with
/// [debugDefaultTargetPlatformOverride].
enum DialTarget { android, ios, windows, other }

/// The platform this build is running on.
DialTarget get dialTarget {
  if (kIsWeb) return DialTarget.other;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return DialTarget.android;
    case TargetPlatform.iOS:
      return DialTarget.ios;
    case TargetPlatform.windows:
      return DialTarget.windows;
    default:
      return DialTarget.other;
  }
}

/// Hysteria2, including `obfs=salamander` and port hopping — options of the
/// protocol, not separate protocols.
const _hysteriaSchemes = <String>{'hysteria2', 'hy2'};

/// Everything the in-process v2ray-core outbound builder can describe.
///
/// One list, because one engine serves all five on both platforms: Android runs
/// it in-process inside hy2bind, and the Windows broker starts the same core as
/// its tunnel engine. `socks` is accepted beside `socks5` so a line written
/// either way reaches the same gate.
const _v2raySchemes = <String>{
  'vless',
  'vmess',
  'trojan',
  'ss',
  'socks5',
  'socks',
};

/// Keys this build reads but never starts.
///
/// WireGuard and AmneziaWG need a userspace tunnel the v2ray-core outbound
/// builder has no way to express, and `vpn://` is a container that expands to
/// another key rather than a dialer of its own. Naming them keeps the badge
/// honest: the row says which protocol it is, instead of looking unsupported.
const kParkedSchemes = <String>{'wireguard', 'amneziawg', 'vpn'};

/// Whether [scheme] may start a system tunnel on [target].
///
/// Hysteria2 on every OS. The v2ray-core family on Android, Windows and iOS:
/// all three link the core — on iOS it arrives inside the same
/// `Hy2bind.xcframework` that carries Hysteria2 — and each has a dataplane for
/// it (VpnService fd, broker engine, packet-flow userspace stack).
bool canDialSchemeOn(DialTarget target, String scheme) {
  final name = scheme.trim().toLowerCase();
  if (_hysteriaSchemes.contains(name)) return true;
  if (_v2raySchemes.contains(name)) {
    return target == DialTarget.android ||
        target == DialTarget.windows ||
        target == DialTarget.ios;
  }
  return false;
}

/// Whether [scheme] may start on the platform this build is running on.
bool canDialScheme(String scheme) => canDialSchemeOn(dialTarget, scheme);

/// The Windows broker's answer. The broker parses the raw URI itself; this
/// mirrors the Flutter gate so the two cannot drift.
bool windowsDialScheme(String scheme) =>
    canDialSchemeOn(DialTarget.windows, scheme);

/// Whether [link] can start on [target].
///
/// A scheme match is not enough. A `vless://` line with XHTTP, or with a
/// transport its engine cannot frame, must stay inactive with a neutral badge
/// rather than fail at start: [buildShareSocksConfig] is the authority for
/// what either share core can describe.
bool canDialLinkOn(DialTarget target, ParsedShareLink link) {
  return canDialSchemeOn(target, link.scheme) &&
      (link.isHysteria2 || buildShareSocksConfig(link) != null);
}

/// Whether [link] can start on the platform this build is running on.
bool canDialLink(ParsedShareLink link) => canDialLinkOn(dialTarget, link);
