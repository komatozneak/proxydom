import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Selling copy and the old product name. Matched case-insensitively.
const sellingTokens = <String>[
  'Premium',
  'Премиум',
  'Platega',
  'тариф',
  'промокод',
  'Оформить',
  'подписк',
  'квота',
  'vpn_teremok_bot',
  'Teremok VPN',
  'Теремок VPN',
  'бот-кассир',
  'кассир',
  // Links and prices a free utility must not carry. The trailing slash on
  // `t.me/` is deliberate: a bare host still belongs to the Telegram host check
  // and to the split-tunnel domain list.
  't.me/',
  '₽',
  'Купить',
  'Оплатить',
];

const brandTokens = <String>[
  'teremok',
  'теремок',
];

/// Tokens that may remain, with a reason. Any other hit in that file fails.
const allowlist = <String, List<String>>{
  // Foreign document suffixes («· Premium») are data, not product copy.
  'lib/features/vpn/data/node_display.dart': ['Premium', 'Премиум', 'Бесплатно'],
  'lib/features/vpn/data/subscription_label.dart': ['Premium'],
  'lib/features/vpn/presentation/locations_screen.dart': ['Premium'],
  'lib/features/home/presentation/widgets/server_card.dart': ['Premium'],
  // Links already sent by the bot stay importable.
  'lib/features/vpn/data/hy2_link_parser.dart': ['teremok'],
  'android/app/src/main/AndroidManifest.xml': ['teremok'],
  'ios/Runner/Info.plist': ['teremok'],
  // Deletes notification channels created by earlier tester builds.
  'android/app/src/main/kotlin/com/proxydom/app/ShadeNotification.kt': ['teremok'],
  // Upload keystore filename. The key itself is not renamed.
  'android/build-sideload.ps1': ['teremok'],
  'android/play-build.ps1': ['teremok'],
  'android/export-upload-cert.ps1': ['teremok'],
  'android/key.properties.template': ['teremok'],
};

const _sourceExt = <String>{
  '.dart',
  '.kt',
  '.swift',
  '.xml',
  '.plist',
  '.yaml',
  '.yml',
  '.arb',
  '.kts',
  '.pro',
  '.go',
  '.ps1',
};

List<String> copyViolations(String relativePath, String text) {
  final allowed = allowlist[relativePath.replaceAll('\\', '/')] ?? const <String>[];
  final hits = <String>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lower = line.toLowerCase();
    for (final token in [...sellingTokens, ...brandTokens]) {
      if (!lower.contains(token.toLowerCase())) continue;
      if (allowed.any((item) => item.toLowerCase() == token.toLowerCase())) {
        continue;
      }
      hits.add('${relativePath.replaceAll('\\', '/')}:${i + 1} $token');
    }
  }
  return hits;
}

void main() {
  test('client source has no selling copy or the old brand', () {
    final hits = <String>[];
    void scan(String relative) {
      final file = File(relative);
      if (!file.existsSync()) return;
      final normalized = relative.replaceAll('\\', '/');
      if (normalized.contains('/test/')) return;
      if (normalized.endsWith('.md') || normalized.endsWith('.pbxproj')) return;
      hits.addAll(copyViolations(normalized, file.readAsStringSync()));
    }

    for (final root in ['lib', 'ios', 'android']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File) continue;
        final ext = entity.path.contains('.')
            ? '.${entity.path.split('.').last}'
            : '';
        if (!_sourceExt.contains(ext)) continue;
        scan(entity.path);
      }
    }
    scan('pubspec.yaml');
    expect(hits, isEmpty, reason: hits.take(30).join('\n'));
  });

  test('a planted selling line is reported with file and line', () {
    final hits = copyViolations('lib/example.dart', 'line\nОформить Premium\n');
    expect(hits, ['lib/example.dart:2 Premium', 'lib/example.dart:2 Оформить']);
  });

  test('a Telegram link is caught, a bare host check is not', () {
    expect(
      copyViolations('lib/l10n/app_ru.arb', '"support": "Написать: t.me/example"\n'),
      ['lib/l10n/app_ru.arb:1 t.me/'],
    );
    expect(
      copyViolations(
        'lib/features/vpn/data/subscription_notice.dart',
        "  return host == 't.me' || host == 'telegram.me';\n",
      ),
      isEmpty,
    );
  });
}
