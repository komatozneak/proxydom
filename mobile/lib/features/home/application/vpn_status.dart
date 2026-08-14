/// Состояние VPN — sealed-иерархия для compile-time exhaustive switch.
///
/// UI mock до Шага 14 (реальный sing-box). Используется в [VpnNotifier]
/// (см. vpn_provider.dart).
sealed class VpnStatus {
  const VpnStatus();
}

/// Не подключён. Стартовое состояние и состояние после `disconnect`.
final class VpnDisconnected extends VpnStatus {
  const VpnDisconnected();
}

/// Подключается. Показываем прогресс-индикатор.
final class VpnConnecting extends VpnStatus {
  const VpnConnecting({required this.progress, this.hint});

  /// 0.0 .. 1.0
  final double progress;

  /// Auto prove label, e.g. «Проверяем Восточную Европу…».
  final String? hint;
}

/// Подключён к серверу по выбранному протоколу.
final class VpnConnected extends VpnStatus {
  const VpnConnected({
    required this.serverName,
    required this.protocol,
    required this.connectedSince,
  });

  final String serverName;
  final String protocol;
  final DateTime connectedSince;
}

/// Ошибка подключения. Показываем сообщение + кнопку "повторить".
final class VpnError extends VpnStatus {
  const VpnError({
    required this.message,
    this.code,
  });

  final String message;

  /// Machine-readable code, e.g. `permission_denied`.
  final String? code;
}

/// Native TUN up may leave sticky [VpnError] (Home Nest stayed red while
/// the tunnel was already live). SOCKS prove still owns the walk.
bool shouldApplyNativeConnected({
  required VpnStatus ui,
  required bool sessionProving,
}) {
  if (sessionProving) return false;
  return ui is! VpnConnected;
}
