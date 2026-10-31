import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proxydom/features/vpn/data/hy2_import_store.dart';
import 'package:proxydom/features/vpn/data/subscription_device.dart';
import 'package:proxydom/features/vpn/data/subscription_notice.dart';

const _link = 'hysteria2://user:pass@203.0.113.12:443/?sni=c.example#Charlie';

void main() {
  tearDown(() {
    subscriptionHeaderSource = loadSubscriptionDeviceHeaders;
  });

  test('markers add the paper plane and the frame', () {
    final notice = composeKeyDescription(
      '{{frame}}Привет {{plane:https://t.me/company_net_support}}{{/frame}}',
    );
    expect(notice.text, 'Привет');
    expect(notice.frame, isTrue);
    expect(notice.planeUrl, 'https://t.me/company_net_support');
    expect(subscriptionPlaneIsTelegram(notice.planeUrl!), isTrue);
  });

  test('a plain announcement is framed unless the document turns the frame off',
      () {
    final framed = subscriptionNotice(announceHeader: 'Для перехода в бота');
    expect(framed.text, 'Для перехода в бота');
    expect(framed.frame, isTrue);

    final open = subscriptionNotice(
      announceHeader: 'Для перехода в бота',
      frameHeader: '0',
    );
    expect(open.frame, isFalse);
  });

  test('base64 announce and a telegram support url survive the body comments',
      () {
    const text =
        'Для перехода в бота нажмите на значок правее\n🔑 sdc91quy Active';
    final encoded = 'base64:${base64Encode(utf8.encode(text))}';
    final notice = subscriptionNotice(
      body: '''
#support-url: https://t.me/company_net_support
#announce: $encoded
$_link
''',
    );
    expect(notice.text, text);
    expect(notice.planeUrl, 'https://t.me/company_net_support');
    expect(notice.frame, isTrue);
    expect(notice.text!.length, lessThanOrEqualTo(subscriptionAnnounceLimit));
  });

  test('a header wins over the same comment in the body', () {
    final notice = subscriptionNotice(
      supportHeader: 'https://t.me/company_net_support',
      announceHeader: 'base64:${base64Encode(utf8.encode('Из заголовка'))}',
      body: '#announce: из тела\n#support-url: https://example.com\n$_link',
    );
    expect(notice.text, 'Из заголовка');
    expect(notice.planeUrl, 'https://t.me/company_net_support');
  });

  test('a non-http plane is dropped', () {
    final notice = composeKeyDescription(
      'Текст',
      planeUrl: 'javascript:alert(1)',
      frame: true,
    );
    expect(notice.planeUrl, isNull);
    expect(notice.frame, isTrue);
    expect(subscriptionPlaneIsTelegram('https://example.com/help'), isFalse);
  });

  test('pasting a document keeps the description on the list', () async {
    SharedPreferences.setMockInitialValues({});
    const text = 'Для перехода в бота нажмите на значок правее';
    final encoded = 'base64:${base64Encode(utf8.encode(text))}';
    await Hy2ImportStore.instance.saveInput('''
#support-url: https://t.me/company_net_support
#announce: $encoded
$_link
''');
    final catalog = (await Hy2ImportStore.instance.catalogs()).single;
    expect(catalog.announce, text);
    expect(catalog.supportUrl, 'https://t.me/company_net_support');
    expect(catalog.announceFrame, isTrue);
  });

  test('an older saved announcement without a frame flag still has a border',
      () async {
    SharedPreferences.setMockInitialValues({
      'hy2_import_v1': jsonEncode({
        'selected': 0,
        'catalogs': [
          {
            'id': 'old',
            'title': 'CompanyNet',
            'lines': [_link],
            'announce': 'base64:${base64Encode(utf8.encode('Старый текст'))}',
            'supportUrl': 'https://t.me/company_net_support',
          },
        ],
      }),
    });
    final catalog = (await Hy2ImportStore.instance.catalogs()).single;
    expect(catalog.announce, 'Старый текст');
    expect(catalog.announceFrame, isTrue);
  });

  test('a fetched document stores the decoded announcement', () async {
    SharedPreferences.setMockInitialValues({});
    subscriptionHeaderSource = () async => {};
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    const text =
        'Для перехода в бота нажмите на значок правее\n❤️ Бесплатный ключ — в боте ❤️';
    server.listen((request) async {
      request.response.headers
        ..set('announce', 'base64:${base64Encode(utf8.encode(text))}')
        ..set('support-url', 'https://t.me/company_net_support');
      request.response.writeln(_link);
      await request.response.close();
    });
    await Hy2ImportStore.instance
        .saveInput('http://127.0.0.1:${server.port}/sub');
    final catalog = (await Hy2ImportStore.instance.catalogs()).single;
    expect(catalog.announce, text);
    expect(catalog.supportUrl, 'https://t.me/company_net_support');
    expect(catalog.announceFrame, isTrue);
  });

  test('a link without an announcement leaves the slot empty', () {
    final notice = profileNotice();
    expect(notice.text, isNull);
    expect(notice.planeUrl, isNull);
    expect(notice.frame, isFalse);
    expect(notice.visible, isFalse);
  });

  test('a document announcement is shown as it arrived', () {
    final notice = profileNotice(
      announce: 'Свой текст',
      supportUrl: 'https://t.me/other',
    );
    expect(notice.text, 'Свой текст');
    expect(notice.planeUrl, 'https://t.me/other');
    expect(notice.frame, isFalse);
  });

  test('a non-http support url does not become a plane', () {
    final notice = profileNotice(
      announce: 'Текст',
      supportUrl: 'javascript:alert(1)',
    );
    expect(notice.text, 'Текст');
    expect(notice.planeUrl, isNull);
  });
}
