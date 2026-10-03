import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/device_info_helper.dart';
import 'share_link_parser.dart';

/// Panel device id: letters, digits, `=` and `-`, 10–64 characters.
///
/// Remnawave ignores any other shape and then answers as if the header
/// was missing.
final RegExp subscriptionDeviceIdPattern = RegExp(r'^[a-zA-Z0-9=-]{10,64}$');

bool isSubscriptionDeviceId(String value) =>
    subscriptionDeviceIdPattern.hasMatch(value);

/// `0.0.0.0` and `0.0.0.1` are placeholders a panel returns instead of a node.
bool isUnspecifiedShareHost(String endpoint) {
  final host = endpoint.split(':').first.trim().toLowerCase();
  return host == '0.0.0.0' ||
      host == '0.0.0.1' ||
      host == '::' ||
      host == '[::]';
}

List<ParsedShareLink> dialableShareLinks(List<ParsedShareLink> links) {
  return [
    for (final link in links)
      if (!isUnspecifiedShareHost(link.endpoint)) link,
  ];
}

enum SubscriptionDocumentProblem { deviceLimit, clientRefused }

/// Stable codes for the import screen and the Home pin.
String subscriptionProblemCode(SubscriptionDocumentProblem problem) {
  return switch (problem) {
    SubscriptionDocumentProblem.deviceLimit => 'device_limit',
    SubscriptionDocumentProblem.clientRefused => 'client_refused',
  };
}

class SubscriptionDocumentException implements Exception {
  const SubscriptionDocumentException(this.problem);

  final SubscriptionDocumentProblem problem;

  String get code => subscriptionProblemCode(problem);
}

/// Placeholder lines are not a server list. Real lines win over a limit header.
SubscriptionDocumentProblem? subscriptionDocumentProblem({
  String? hwidMaxDevices,
  required List<ParsedShareLink> links,
}) {
  if (links.isEmpty || dialableShareLinks(links).isNotEmpty) return null;
  if (_headerOn(hwidMaxDevices)) {
    return SubscriptionDocumentProblem.deviceLimit;
  }
  return SubscriptionDocumentProblem.clientRefused;
}

bool _headerOn(String? value) {
  final text = value?.trim().toLowerCase();
  return text == 'true' || text == '1';
}

/// Headers the document host uses to tell installs apart.
///
/// `x-hwid` is the only required field. The User-Agent stays this app's.
Map<String, String> subscriptionDeviceHeaders({
  required String deviceId,
  String operatingSystem = '',
  String osVersion = '',
  String deviceModel = '',
}) {
  final id = deviceId.trim();
  if (!isSubscriptionDeviceId(id)) return const {};
  final headers = <String, String>{'x-hwid': id};
  void put(String key, String value) {
    final clean = value.replaceAll(RegExp(r'[\r\n]'), ' ').trim();
    if (clean.isEmpty) return;
    headers[key] = clean.length <= 64 ? clean : clean.substring(0, 64);
  }

  put('x-device-os', operatingSystem);
  put('x-ver-os', osVersion);
  put('x-device-model', deviceModel);
  return headers;
}

String subscriptionOsLabel() {
  if (kIsWeb) return '';
  if (Platform.isAndroid) return 'Android';
  if (Platform.isIOS) return 'iOS';
  if (Platform.isMacOS) return 'macOS';
  if (Platform.isWindows) return 'Windows';
  if (Platform.isLinux) return 'Linux';
  return '';
}

typedef SubscriptionHeaderSource = Future<Map<String, String>> Function();

/// Tests replace this. Production reads the stable install id.
SubscriptionHeaderSource subscriptionHeaderSource = loadSubscriptionDeviceHeaders;

Future<Map<String, String>> loadSubscriptionDeviceHeaders() async {
  final id = await SubscriptionDeviceId.instance.getOrCreate();
  final model = await DeviceInfoHelper.getDeviceModelName();
  final version = kIsWeb ? '' : Platform.operatingSystemVersion;
  return subscriptionDeviceHeaders(
    deviceId: id,
    operatingSystem: subscriptionOsLabel(),
    osVersion: version,
    deviceModel: model,
  );
}

/// Stable id sent only to a document the person pasted. Not an account seat.
class SubscriptionDeviceId {
  SubscriptionDeviceId._();

  static final SubscriptionDeviceId instance = SubscriptionDeviceId._();

  static const _key = 'pd.subscription_device_id';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'proxydom_secure_tokens',
      preferencesKeyPrefix: 'pd_',
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<String> getOrCreate() async {
    final existing = await _storage.read(key: _key);
    if (existing != null && isSubscriptionDeviceId(existing)) return existing;
    final created = _uuidV4();
    await _storage.write(key: _key, value: created);
    return created;
  }

  static String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
    final text = bytes.map(hex).join();
    return '${text.substring(0, 8)}-${text.substring(8, 12)}-'
        '${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
  }
}
