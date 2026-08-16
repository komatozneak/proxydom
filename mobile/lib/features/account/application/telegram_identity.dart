import '../../home/application/vpn_status.dart';

/// Telegram is blocked in RF without a tunnel — only offer TG identity
/// after Teremok VPN is connected.
bool telegramIdentityAllowed(VpnStatus status) => status is VpnConnected;
