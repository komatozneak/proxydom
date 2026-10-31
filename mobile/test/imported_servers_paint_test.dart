import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/hy2_import_store.dart';
import 'package:proxydom/features/vpn/data/share_link_parser.dart';

void main() {
  const stand =
      'hysteria2://standHy2pass@95.182.81.27:20001'
      '?sni=stand.company-net.test&insecure=1#hy2';

  test('local lines paint before a refresh that never finishes', () async {
    final link = parseShareLink(stand);
    final painted = <String>[];
    final refreshEntered = Completer<void>();
    final hung = Completer<void>();

    final pending = paintImportedServers(
      readLocal: () async => [link],
      refresh: () {
        if (!refreshEntered.isCompleted) refreshEntered.complete();
        return hung.future;
      },
      paint: (links) async {
        painted.add(links.single.endpoint);
      },
    );

    await refreshEntered.future;
    expect(painted, ['95.182.81.27:20001']);

    var finished = false;
    unawaited(pending.whenComplete(() => finished = true));
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
  });

  test('a failed refresh leaves the painted list', () async {
    final link = parseShareLink(stand);
    final painted = <String>[];

    await paintImportedServers(
      readLocal: () async => [link],
      refresh: () => throw TimeoutException('saved url'),
      paint: (links) async {
        painted.add(links.single.endpoint);
      },
    );

    expect(painted, ['95.182.81.27:20001']);
  });
}
