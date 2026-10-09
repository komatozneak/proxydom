/// The Imported-Document Dial Set (ADR 035).
///
/// Two dial sets exist and must not be confused:
///
/// * **Catalog Dial Set** — the nodes the catalog and the bot serve. Those are
///   Hysteria2 only (ADR 018) and are not decided here.
/// * **Imported-Document Dial Set** — lines the person pasted, or pulled from a
///   foreign HTTPS document. This file is the single authority for what may
///   start there, per platform.
///
/// The parser stays wider than this set (ADR 033 §3, ADR 035 §5): Trojan,
/// Shadowsocks, and VMess are still read and still kept in the document, they
/// simply cannot start. VLESS is admitted only where the engine can describe
/// the line. Reality and XHTTP are not in v2ray-core (ADR 036), so
/// [canDialLinkOn] refuses them even where the scheme itself is allowed.
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
/// protocol, not separate protocols (ADR 033 §5).
const _hysteriaSchemes = <String>{'hysteria2', 'hy2'};

/// VLESS. Reality is not a separate scheme; [canDialLinkOn] refuses it.
const _vlessSchemes = <String>{'vless'};

/// Schemes the parser reads but no platform may start (ADR 035 §5).
const kParkedSchemes = <String>{'vmess', 'trojan', 'ss'};

/// Whether [scheme] may start a system tunnel on [target].
///
/// Hysteria2 on every OS. VLESS on Android and Windows: Android runs
/// v2ray-core in-process inside hy2bind, and the Windows broker starts the same
/// MIT core as its tunnel engine. Both are the engine from ADR 035/036.
///
/// iOS has no VLESS engine and stays false. That is the only platform left, and
/// it comes off with its own engine, in its own task — not in this file ahead
/// of it.
bool canDialSchemeOn(DialTarget target, String scheme) {
  final name = scheme.trim().toLowerCase();
  if (_hysteriaSchemes.contains(name)) return true;
  if (_vlessSchemes.contains(name)) {
    return target == DialTarget.android || target == DialTarget.windows;
  }
  return false;
}

/// Whether [scheme] may start on the platform this build is running on.
bool canDialScheme(String scheme) => canDialSchemeOn(dialTarget, scheme);

/// The Windows broker's answer. Moved here from `ios_store_gates.dart` so the
/// gate has one home. The broker parses the raw URI itself; this mirrors the
/// Flutter gate so the two cannot drift. Today that answer is Hysteria2 and
/// VLESS over TCP or WebSocket.
bool windowsDialScheme(String scheme) =>
    canDialSchemeOn(DialTarget.windows, scheme);

/// Whether [link] can start on [target].
///
/// A scheme match is not enough. A `vless://` line with Reality or XHTTP must
/// stay inactive, with a neutral badge, rather than fail at start: v2ray-core
/// cannot describe it, and [buildShareSocksConfig] is the authority for that.
bool canDialLinkOn(DialTarget target, ParsedShareLink link) {
  return canDialSchemeOn(target, link.scheme) &&
      (link.isHysteria2 || buildShareSocksConfig(link) != null);
}

/// Whether [link] can start on the platform this build is running on.
bool canDialLink(ParsedShareLink link) => canDialLinkOn(dialTarget, link);
