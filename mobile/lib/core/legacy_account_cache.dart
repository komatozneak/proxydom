import 'package:shared_preferences/shared_preferences.dart';

import 'install_id_storage.dart';
import 'token_storage.dart';

const _wipedKey = 'route_document_legacy_wiped_v1';

/// Drops the old catalog cache, session tokens, and install id once.
///
/// Saved route documents stay. A later launch does not wipe them again.
Future<void> discardLegacyAccountCache() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_wipedKey) == true) return;
  await prefs.remove('vpn_nodes_cache_v1');
  await prefs.remove('selected_region_id');
  await TokenStorage.instance.clear();
  await InstallIdStorage.instance.clearForTests();
  await prefs.setBool(_wipedKey, true);
}
