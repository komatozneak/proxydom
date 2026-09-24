import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/hy2_import_store.dart';
import '../data/share_link_parser.dart';

/// Imported profiles. The first event is the saved list; later events follow
/// [Hy2ImportStore.changes] so a shell tab does not stay on its first load.
final importedProfilesProvider = StreamProvider<List<ParsedShareLink>>((ref) async* {
  final store = Hy2ImportStore.instance;
  yield await store.load();
  await for (final _ in store.changes) {
    yield await store.load();
  }
});
