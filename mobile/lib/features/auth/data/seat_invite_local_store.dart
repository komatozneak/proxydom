import 'package:shared_preferences/shared_preferences.dart';

/// Remembers seat codes minted on this install so we refuse self-accept
/// even when the API build is older than the `own_seat_code` guard.
class SeatInviteLocalStore {
  SeatInviteLocalStore._();
  static final SeatInviteLocalStore instance = SeatInviteLocalStore._();

  static const _prefsKey = 'seat_codes_minted_v1';
  static const _maxRemembered = 32;

  /// Same normalization as backend `normalize_seat_code`.
  static String normalize(String raw) {
    return raw.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  Future<void> rememberMinted(String code) async {
    final n = normalize(code);
    if (n.length < 4) return;
    final prefs = await SharedPreferences.getInstance();
    final list = List<String>.from(prefs.getStringList(_prefsKey) ?? const []);
    list.remove(n);
    list.add(n);
    while (list.length > _maxRemembered) {
      list.removeAt(0);
    }
    await prefs.setStringList(_prefsKey, list);
  }

  Future<bool> wasMintedHere(String code) async {
    final n = normalize(code);
    if (n.length < 4) return false;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? const [];
    return list.contains(n);
  }
}
