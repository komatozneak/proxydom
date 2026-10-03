import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/hy2_import_store.dart';
import 'package:proxydom/features/vpn/data/share_link_parser.dart';
import 'package:proxydom/features/vpn/data/subscription_device.dart';
import 'package:proxydom/features/vpn/data/subscription_label.dart';

void main() {
  tearDown(() {
    subscriptionHeaderSource = loadSubscriptionDeviceHeaders;
  });

  test('profile-title with a base64 prefix becomes text', () {
    expect(
      decodeProfileTitle('base64:UHJvc3RvY29ubmVjdFZQTg=='),
      'ProstoconnectVPN',
    );
    expect(decodeProfileTitle('Plain title'), 'Plain title');
  });

  test('a percent-encoded vless remark is the server name', () {
    final link = parseShareLink(
      'vless://11111111-1111-4111-8111-111111111111@203.0.113.8:443'
      '#%D0%9F%D1%80%D0%B8%D0%BB%D0%BE%D0%B6%D0%B5%D0%BD%D0%B8%D0%B5',
    );
    expect(link.name, 'Приложение');
    expect(link.name.contains('%'), isFalse);
  });

  test('device headers keep this app user agent slot free', () {
    final headers = subscriptionDeviceHeaders(
      deviceId: 'abcdef1234',
      operatingSystem: 'Android',
      osVersion: '14',
      deviceModel: 'Pixel',
    );
    expect(headers['x-hwid'], 'abcdef1234');
    expect(headers['x-device-os'], 'Android');
    expect(headers.containsKey('user-agent'), isFalse);
    expect(subscriptionDeviceHeaders(deviceId: 'short'), isEmpty);
  });

  test('a placeholder host is not a server list', () {
    final stub = parseShareLink(
      'vless://00000000-0000-0000-0000-000000000000@0.0.0.0:1#stub',
    );
    expect(
      subscriptionDocumentProblem(links: [stub]),
      SubscriptionDocumentProblem.clientRefused,
    );
    expect(
      subscriptionDocumentProblem(hwidMaxDevices: 'true', links: [stub]),
      SubscriptionDocumentProblem.deviceLimit,
    );
    final real = parseShareLink(
      'vless://11111111-1111-4111-8111-111111111111@203.0.113.8:443#Node',
    );
    expect(
      subscriptionDocumentProblem(hwidMaxDevices: 'true', links: [stub, real]),
      isNull,
    );
    expect(dialableShareLinks([stub, real]), [real]);
  });

  test('document fetch sends the device id and reads the profile title', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    String? hwid;
    String? userAgent;
    server.listen((request) async {
      hwid = request.headers.value('x-hwid');
      userAgent = request.headers.value(HttpHeaders.userAgentHeader);
      request.response.headers
        ..set('profile-title', 'base64:UHJvc3RvY29ubmVjdFZQTg==')
        ..set(
          'subscription-userinfo',
          'upload=0; download=0; total=44040192; expire=0',
        );
      request.response.writeln(
        'vless://11111111-1111-4111-8111-111111111111@203.0.113.8:443#Node',
      );
      await request.response.close();
    });
    subscriptionHeaderSource = () async => subscriptionDeviceHeaders(
          deviceId: 'abcdef1234',
          operatingSystem: 'Android',
        );
    final preview = await Hy2ImportStore.instance.previewSubscription(
      'http://127.0.0.1:${server.port}/sub',
    );
    expect(hwid, 'abcdef1234');
    expect(userAgent, 'ProxyDom/1.0');
    expect(preview.title, 'ProstoconnectVPN');
    expect(preview.links.single.endpoint, '203.0.113.8:443');
  });

  test('a device-limit placeholder is refused before it can be saved', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.headers.set('x-hwid-max-devices-reached', 'true');
      request.response.writeln(
        'vless://00000000-0000-0000-0000-000000000000@0.0.0.1:1#stub',
      );
      await request.response.close();
    });
    subscriptionHeaderSource = () async =>
        subscriptionDeviceHeaders(deviceId: 'abcdef1234');
    expect(
      Hy2ImportStore.instance.previewSubscription(
        'http://127.0.0.1:${server.port}/sub',
      ),
      throwsA(
        isA<SubscriptionDocumentException>().having(
          (error) => error.problem,
          'problem',
          SubscriptionDocumentProblem.deviceLimit,
        ),
      ),
    );
  });
}
