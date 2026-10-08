import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/home/application/vpn_status.dart';
import 'package:proxydom/features/vpn/data/vpn_session_snapshot.dart';
import 'package:proxydom/features/vpn/domain/vpn_connect_error.dart';
import 'package:proxydom/l10n/app_localizations_en.dart';
import 'package:proxydom/l10n/app_localizations_ru.dart';

void main() {
  group('parseSocksProbeFailure', () {
    test('parses native failStart message', () {
      final parsed = parseSocksProbeFailure(
        'eu-primary@204.11.2.216: SOCKS HTTPS probe failed',
      );
      expect(parsed?.nodeId, 'eu-primary');
      expect(parsed?.host, '204.11.2.216');
    });

    test('returns null for unrelated errors', () {
      expect(parseSocksProbeFailure('Xray start failed'), isNull);
    });

    test('parses failStart when the server includes a port', () {
      final parsed = parseSocksProbeFailure(
        'eu-hy2-1@217.60.3.9:443: SOCKS HTTPS probe failed',
      );
      expect(parsed?.nodeId, 'eu-hy2-1');
      expect(parsed?.host, '217.60.3.9');
    });
  });

  group('vpnErrorFromNativeDetail', () {
    test('maps probe fail to server_probe_failed code', () {
      final err = vpnErrorFromNativeDetail(
        'eu-primary@204.11.2.216: SOCKS HTTPS probe failed',
      );
      expect(err.code, kVpnProbeFailedErrorCode);
      expect(err.message, 'eu-primary');
    });

    test('maps Auto prove miss to path_incompatible', () {
      final err = vpnErrorFromNativeDetail(
        'path_incompatible: auto: no candidate passed data-plane prove',
      );
      expect(err.code, kVpnPathIncompatibleErrorCode);
    });

    test('maps session PathIncompatible to path_incompatible', () {
      final err = vpnErrorFromSession(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.error,
          generation: 1,
          reason: VpnSessionReason.pathIncompatible,
          detail:
              'path_incompatible: auto: no candidate passed data-plane prove',
        ),
      );
      expect(err.code, kVpnPathIncompatibleErrorCode);
    });

    test('maps ported SOCKS probe to server_probe_failed', () {
      final err = vpnErrorFromNativeDetail(
        'eu-hy2-1@217.60.3.9:443: SOCKS HTTPS probe failed',
      );
      expect(err.code, kVpnProbeFailedErrorCode);
      expect(err.message, 'eu-hy2-1');
    });

    test('masquerade 405 is a node refusal, not the raw status', () {
      final err = vpnErrorFromNativeDetail(
        'hy2 client: authentication error, HTTP status code: 405',
      );
      expect(err.code, kVpnNodeAuthRefusedErrorCode);
      expect(err.message, kVpnNodeAuthRefusedErrorCode);
      expect(err.message, isNot(contains('405')));
    });

    test('the refusal copy names a denied session, not the raw 405', () {
      expect(
        AppL10nRu().homeNodeAuthRefused,
        'Узел отклонил аутентификацию. Сессия не разрешена: трафик периода закончился или ключ отозван.',
      );
      expect(
        AppL10nEn().homeNodeAuthRefused,
        contains('traffic is used up'),
      );
    });

    test('a transport failure stays a transport failure', () {
      final err = vpnErrorFromNativeDetail('connection reset by peer');
      expect(err.code, isNull);
      expect(err.message, 'vpn: connection reset by peer');
    });

    test('falls back when detail empty', () {
      final err = vpnErrorFromNativeDetail(
        null,
        fallbackMessage: 'Failed to start VPN service',
      );
      expect(err.code, isNull);
      expect(err.message, 'Failed to start VPN service');
    });
  });

  group('auto mint empty classification', () {
    test('DNS skips are api_unreachable', () {
      expect(
        autoMintEmptyFailCode(const [
          AutoMintSkipKind.connection,
          AutoMintSkipKind.connection,
        ]),
        kVpnApiUnreachableErrorCode,
      );
    });

    test('a non-transport skip stays path_incompatible', () {
      expect(
        autoMintEmptyFailCode(const [
          AutoMintSkipKind.connection,
          AutoMintSkipKind.other,
        ]),
        kVpnPathIncompatibleErrorCode,
      );
      expect(
        autoMintEmptyFailCode(const <AutoMintSkipKind>[]),
        kVpnPathIncompatibleErrorCode,
      );
    });

    test('connection Dio and SocketException are control-plane', () {
      expect(
        isControlPlaneTransportError(
          const SocketException('Failed host lookup'),
        ),
        isTrue,
      );
      final opts = RequestOptions(path: '/vpn/config');
      expect(
        isControlPlaneTransportError(
          DioException(
            requestOptions: opts,
            type: DioExceptionType.connectionError,
            error: const SocketException(
              'Failed host lookup: api.teremokconnect.online',
            ),
          ),
        ),
        isTrue,
      );
      expect(
        isControlPlaneTransportError(
          DioException(
            requestOptions: opts,
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: opts, statusCode: 402),
          ),
        ),
        isFalse,
      );
    });
  });

  group('ownsConnectUi', () {
    test('is true during the walk', () {
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.proving,
          generation: 1,
        ).ownsConnectUi,
        isTrue,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.binding,
          generation: 1,
        ).ownsConnectUi,
        isTrue,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.tunUp,
          generation: 1,
        ).ownsConnectUi,
        isTrue,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.coreStarting,
          generation: 1,
        ).ownsConnectUi,
        isTrue,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.error,
          generation: 1,
          reason: VpnSessionReason.pathIncompatible,
        ).ownsConnectUi,
        isFalse,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.connectedHealthy,
          generation: 1,
        ).ownsConnectUi,
        isFalse,
      );
    });

    test('idle does not drop Connecting while walk or proving', () {
      expect(
        connectingIdleShouldDrop(
          walkActive: true,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.idle,
        ),
        isFalse,
      );
      expect(
        connectingIdleShouldDrop(
          walkActive: false,
          sessionOwnsUi: true,
          lastPhase: VpnSessionPhase.idle,
        ),
        isFalse,
      );
      expect(
        connectingIdleShouldDrop(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.proving,
        ),
        isFalse,
      );
      expect(
        connectingIdleShouldDrop(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.unknown,
        ),
        isFalse,
      );
      expect(
        connectingIdleShouldDrop(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.idle,
        ),
        isTrue,
      );
      expect(
        connectingIdleShouldDrop(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.connectedHealthy,
        ),
        isFalse,
      );
      expect(
        nativeIdleMustNotDemote(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.connectedHealthy,
        ),
        isTrue,
      );
      expect(
        nativeIdleMustNotDemote(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.proving,
        ),
        isTrue,
      );
      expect(
        nativeIdleMustNotDemote(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.idle,
        ),
        isFalse,
      );
      expect(
        nativeIdleMustNotDemote(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.unknown,
          uiConnected: true,
          nativeSyncComplete: true,
        ),
        isTrue,
      );
      expect(
        nativeIdleMustNotDemote(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.unknown,
          uiConnected: false,
          nativeSyncComplete: false,
        ),
        isTrue,
      );
      expect(
        shouldIgnoreRegressiveIdleSnapshot(
          incoming: VpnSessionPhase.idle,
          lastPhase: VpnSessionPhase.proving,
          walkActive: false,
          sessionOwnsUi: false,
        ),
        isTrue,
      );
      expect(
        shouldIgnoreRegressiveIdleSnapshot(
          incoming: VpnSessionPhase.unknown,
          lastPhase: VpnSessionPhase.connectedHealthy,
          walkActive: false,
          sessionOwnsUi: false,
        ),
        isTrue,
      );
      expect(
        shouldIgnoreRegressiveIdleSnapshot(
          incoming: VpnSessionPhase.idle,
          lastPhase: VpnSessionPhase.idle,
          walkActive: false,
          sessionOwnsUi: false,
        ),
        isFalse,
      );
      expect(
        shouldIgnoreRegressiveIdleSnapshot(
          incoming: VpnSessionPhase.connectedHealthy,
          lastPhase: VpnSessionPhase.proving,
          walkActive: false,
          sessionOwnsUi: false,
        ),
        isFalse,
      );
      expect(
        shouldIgnoreRegressiveIdleSnapshot(
          incoming: VpnSessionPhase.idle,
          lastPhase: VpnSessionPhase.stopping,
          walkActive: false,
          sessionOwnsUi: false,
        ),
        isFalse,
      );
      expect(
        shouldIgnoreRegressiveIdleSnapshot(
          incoming: VpnSessionPhase.idle,
          lastPhase: VpnSessionPhase.stopping,
          walkActive: true,
          sessionOwnsUi: true,
          userStopping: true,
        ),
        isFalse,
      );
      expect(
        nativeIdleMustNotDemote(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.connectedHealthy,
          userStopping: true,
        ),
        isFalse,
      );
      expect(
        shouldIgnoreRegressiveIdleSnapshot(
          incoming: VpnSessionPhase.idle,
          lastPhase: VpnSessionPhase.connectedHealthy,
          walkActive: false,
          sessionOwnsUi: false,
          userStopping: true,
        ),
        isFalse,
      );
      expect(
        connectingIdleShouldDrop(
          walkActive: false,
          sessionOwnsUi: false,
          lastPhase: VpnSessionPhase.connectedHealthy,
          userStopping: true,
        ),
        isTrue,
      );
    });

    test('ignoresNativeConnected only while proving', () {
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.proving,
          generation: 1,
        ).ignoresNativeConnected,
        isTrue,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.binding,
          generation: 1,
        ).ignoresNativeConnected,
        isFalse,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.tunUp,
          generation: 1,
        ).ignoresNativeConnected,
        isFalse,
      );
      expect(
        const VpnSessionSnapshot(
          phase: VpnSessionPhase.coreStarting,
          generation: 1,
        ).ignoresNativeConnected,
        isFalse,
      );
    });
  });

  group('shouldApplyNativeConnected', () {
    test('heals sticky VpnError when not proving', () {
      expect(
        shouldApplyNativeConnected(
          ui: const VpnError(message: 'fail'),
          sessionProving: false,
        ),
        isTrue,
      );
    });

    test('does not overwrite Connected or heal during SOCKS prove', () {
      expect(
        shouldApplyNativeConnected(
          ui: VpnConnected(
            serverName: 'EU',
            protocol: 'hysteria',
            connectedSince: DateTime.utc(2026, 8, 14),
          ),
          sessionProving: false,
        ),
        isFalse,
      );
      expect(
        shouldApplyNativeConnected(
          ui: const VpnError(message: 'fail'),
          sessionProving: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldRefuseEnterConnected', () {
    test('aborts stale connect generation after Nest stop', () {
      expect(
        shouldRefuseEnterConnected(
          sessionProving: false,
          connectGen: 3,
          currentGen: 4,
          walkActive: false,
          sessionOwnsUi: false,
          nativeConnected: true,
        ),
        isTrue,
      );
    });

    test('refuses Connected paint when native is idle and walk is over', () {
      expect(
        shouldRefuseEnterConnected(
          sessionProving: false,
          connectGen: 2,
          currentGen: 2,
          walkActive: false,
          sessionOwnsUi: false,
          nativeConnected: false,
        ),
        isTrue,
      );
    });

    test('allows paint during walk even if getStatus flaps idle', () {
      expect(
        shouldRefuseEnterConnected(
          sessionProving: false,
          connectGen: 2,
          currentGen: 2,
          walkActive: true,
          sessionOwnsUi: false,
          nativeConnected: false,
        ),
        isFalse,
      );
    });

    test('refuses Connected paint while the user is stopping', () {
      expect(
        shouldRefuseEnterConnected(
          sessionProving: false,
          connectGen: 2,
          currentGen: 2,
          walkActive: false,
          sessionOwnsUi: false,
          nativeConnected: true,
          userStopping: true,
        ),
        isTrue,
      );
    });

    test('allows paint when native is connected and generation matches', () {
      expect(
        shouldRefuseEnterConnected(
          sessionProving: false,
          connectGen: 2,
          currentGen: 2,
          walkActive: false,
          sessionOwnsUi: false,
          nativeConnected: true,
        ),
        isFalse,
      );
    });
  });

  group('isWifiUnderlying', () {
    test('treats wlan and wifi iface as Wi-Fi', () {
      expect(isWifiUnderlying(iface: 'wlan0'), isTrue);
      expect(isWifiUnderlying(iface: 'wlan1'), isTrue);
      expect(isWifiUnderlying(iface: 'wifi0'), isTrue);
      expect(
        isWifiUnderlying(
          iface: 'rmnet0',
          transport: VpnPathTransport.wifi,
        ),
        isTrue,
      );
    });

    test('does not treat cellular as Wi-Fi', () {
      expect(isWifiUnderlying(iface: 'rmnet0'), isFalse);
      expect(
        isWifiUnderlying(
          iface: 'wlan0',
          transport: VpnPathTransport.cellular,
        ),
        isFalse,
      );
    });

    test('does not treat native unknown placeholder as Wi-Fi', () {
      expect(isWifiUnderlying(iface: '(unknown)'), isFalse);
      expect(isWifiUnderlying(iface: 'unknown'), isFalse);
      expect(isWifiUnderlying(iface: ''), isFalse);
    });
  });

  group('shouldRetryAutoOnWifi', () {
    test('retries once on Wi-Fi only', () {
      expect(
        shouldRetryAutoOnWifi(
          alreadyRetried: false,
          userStopping: false,
          isWifi: true,
        ),
        isTrue,
      );
    });

    test('does not retry twice or after Nest stop', () {
      expect(
        shouldRetryAutoOnWifi(
          alreadyRetried: true,
          userStopping: false,
          isWifi: true,
        ),
        isFalse,
      );
      expect(
        shouldRetryAutoOnWifi(
          alreadyRetried: false,
          userStopping: true,
          isWifi: true,
        ),
        isFalse,
      );
      expect(
        shouldRetryAutoOnWifi(
          alreadyRetried: false,
          userStopping: false,
          isWifi: false,
        ),
        isFalse,
      );
    });
  });
}
