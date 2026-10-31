import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The Dart half of the client license gate; the Go engine has its own in
// hysteria-bind/license_guard_test.go. Both apply the same rule: the client
// ships under store terms, which GPL-family licenses forbid layering on top of
// them, so a copyleft package anywhere in the resolved graph fails the build.

const _disallowed = <(String, List<String>)>[
  ('AGPL', ['gnu affero general public license']),
  ('LGPL', ['gnu lesser general public license']),
  ('LGPL', ['gnu library general public license']),
  ('GPL', ['gnu general public license']),
  ('SSPL', ['server side public license']),
  ('EUPL', ['european union public licence']),
  ('CC-BY-NC', ['attribution-noncommercial']),
];

const _allowed = <(String, List<String>)>[
  ('MPL-2.0', ['mozilla public license version 2.0']),
  ('MPL-2.0', ['mozilla public license, v. 2.0']),
  ('Apache-2.0', ['apache license', 'version 2.0']),
  ('MIT', ['permission is hereby granted, free of charge']),
  ('BSD', ['redistribution and use in source and binary forms']),
  ('ISC', ['permission to use, copy, modify, and/or distribute this software']),
  ('Zlib', ['altered source versions must be plainly marked as such']),
];

// MPL-2.0 defines "Secondary License" by naming the GNU licenses. That is not
// a grant of GPL, so the definition is cut before the GNU markers are matched.
const _mplSecondaryLicenses =
    '"secondary license" means either the gnu general public license, '
    'version 2.0, the gnu lesser general public license, version 2.1, the gnu '
    'affero general public license, version 3.0, or any later versions of '
    'those licenses.';

final _licenseFile = RegExp(r'^(licen[cs]e|copying|notice)', caseSensitive: false);

String _normalise(String text) => text
    .replaceAll('“', '"')
    .replaceAll('”', '"')
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .join(' ');

bool _all(String text, List<String> markers) => markers.every(text.contains);

/// Returns (allowed classes, disallowed classes) found in one license text.
(Set<String>, Set<String>) classifyLicense(String raw) {
  final norm = _normalise(raw);
  final gnu = norm.contains('mozilla public license')
      ? norm.replaceAll(_mplSecondaryLicenses, '')
      : norm;
  final bad = {
    for (final (cls, m) in _disallowed)
      if (_all(gnu, m)) cls,
  };
  final ok = {
    for (final (cls, m) in _allowed)
      if (_all(norm, m)) cls,
  };
  return (ok, bad);
}

Directory _packageRoot(Map<String, dynamic> pkg, Uri configUri) {
  final root = configUri.resolve(pkg['rootUri'] as String);
  final path = root.path.endsWith('/') ? root : Uri.parse('$root/');
  return Directory.fromUri(path);
}

List<File> _filesIn(Directory dir) => dir
    .listSync()
    .whereType<File>()
    .where((f) => _licenseFile.hasMatch(f.uri.pathSegments.last))
    .toList();

/// Packages inside the Flutter SDK (flutter_test, flutter_localizations, ...)
/// carry no file of their own; they are covered by the SDK's root LICENSE.
List<File> _licenseFiles(Directory dir) {
  var d = dir;
  for (var depth = 0; depth < 3; depth++) {
    final found = _filesIn(d);
    if (found.isNotEmpty) return found;
    if (d.parent.path == d.path) break;
    d = d.parent;
  }
  return const [];
}

void main() {
  group('classifyLicense', () {
    test('rejects the GPL family', () {
      expect(
        classifyLicense('GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007').$2,
        contains('GPL'),
      );
      expect(
        classifyLicense('GNU AFFERO GENERAL PUBLIC LICENSE').$2,
        contains('AGPL'),
      );
      expect(
        classifyLicense('GNU LESSER GENERAL PUBLIC LICENSE Version 2.1').$2,
        contains('LGPL'),
      );
      expect(classifyLicense('Server Side Public License').$2, contains('SSPL'));
    });

    test('accepts MPL-2.0 even though it names the GNU licenses', () {
      const mpl = 'Mozilla Public License Version 2.0\n'
          '1.12. "Secondary License"\n'
          '    means either the GNU General Public License, Version 2.0, the GNU\n'
          '    Lesser General Public License, Version 2.1, the GNU Affero General\n'
          '    Public License, Version 3.0, or any later versions of those\n'
          '    licenses.';
      final (ok, bad) = classifyLicense(mpl);
      expect(bad, isEmpty);
      expect(ok, contains('MPL-2.0'));
    });

    test('still rejects GPL text that sits next to an MPL notice', () {
      const mixed = 'Mozilla Public License Version 2.0\n'
          'This file is also under the GNU General Public License v3.';
      expect(classifyLicense(mixed).$2, contains('GPL'));
    });

    test('accepts MIT', () {
      final (ok, bad) = classifyLicense(
        'Permission is hereby granted, free of charge, to any person',
      );
      expect(bad, isEmpty);
      expect(ok, contains('MIT'));
    });
  });

  test('every resolved Dart package carries a permissive license', () {
    final config = File('.dart_tool/package_config.json');
    if (!config.existsSync()) {
      fail('run `flutter pub get` first: .dart_tool/package_config.json is missing');
    }
    final json = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
    final packages = (json['packages'] as List).cast<Map<String, dynamic>>();
    final problems = <String>[];
    var scanned = 0;
    for (final pkg in packages) {
      final name = pkg['name'] as String;
      if (name == 'proxydom') continue;
      final dir = _packageRoot(pkg, config.absolute.uri);
      if (!dir.existsSync()) {
        problems.add('$name: package root ${dir.path} is missing');
        continue;
      }
      final files = _licenseFiles(dir);
      final allowed = <String>{};
      for (final f in files) {
        final (ok, bad) = classifyLicense(f.readAsStringSync());
        for (final cls in bad) {
          problems.add('$name: forbidden license $cls in ${f.uri.pathSegments.last}');
        }
        allowed.addAll(ok);
      }
      if (allowed.isEmpty && !problems.any((p) => p.startsWith('$name:'))) {
        problems.add('$name: no recognised permissive license file');
      }
      scanned++;
    }
    expect(scanned, greaterThan(50), reason: 'the graph looks unresolved');
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
