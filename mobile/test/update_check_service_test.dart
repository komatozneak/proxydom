import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:proxydom/core/updates/update_check_service.dart';

const _playProxy =
    'https://play.google.com/store/apps/details?id=com.proxy.dom';
const _playTeremok = 'https://play.google.com/store/apps/details'
    '?id=com.teremok.connect.teremok_connect';
const _apk = 'https://dl.proxydom.su/ProxyDom-1.0.1.apk';
const _siteMsi = 'https://proxydom.su/downloads/ProxyDom-1.0.1.msi';

AppVersionInfo _remote({
  int buildNumber = 2044,
  String downloadUrl = _apk,
  String releaseNotes = '',
  String windowsVersion = '',
  String windowsDownloadUrl = '',
  String windowsReleaseNotes = '',
}) {
  return AppVersionInfo(
    version: '1.0.1',
    buildNumber: buildNumber,
    downloadUrl: downloadUrl,
    releaseNotes: releaseNotes,
    windowsVersion: windowsVersion,
    windowsDownloadUrl: windowsDownloadUrl,
    windowsReleaseNotes: windowsReleaseNotes,
  );
}

void main() {
  group('UpdateCheckService.isAllowedDownloadUrl', () {
    test('accepts the Proxy Dom Play page', () {
      expect(
        UpdateCheckService.isAllowedDownloadUrl(
          _playProxy,
          target: UpdateTarget.android,
        ),
        isTrue,
      );
      expect(UpdateCheckService.isAllowedDownloadUrl(_playProxy), isTrue);
    });

    test('accepts HTTPS downloads from the two Proxy Dom hosts', () {
      expect(UpdateCheckService.isAllowedDownloadUrl(_apk), isTrue);
      expect(UpdateCheckService.isAllowedDownloadUrl(_siteMsi), isTrue);
      expect(
        UpdateCheckService.isAllowedDownloadUrl(
          'https://proxydom.su/downloads/ProxyDom-1.0.1.apk?build=22',
        ),
        isTrue,
      );
    });

    test('rejects the Teremok Play package', () {
      expect(UpdateCheckService.isAllowedDownloadUrl(_playTeremok), isFalse);
    });

    test('rejects another package id and duplicate ids', () {
      expect(
        UpdateCheckService.isAllowedDownloadUrl(
          'https://play.google.com/store/apps/details?id=com.proxy.dom.extra',
        ),
        isFalse,
      );
      expect(
        UpdateCheckService.isAllowedDownloadUrl(
          'https://play.google.com/store/apps/details'
          '?id=com.proxy.dom&id=com.teremok.connect.teremok_connect',
        ),
        isFalse,
      );
    });

    test('rejects http even on a trusted host', () {
      expect(
        UpdateCheckService.isAllowedDownloadUrl(
          'http://proxydom.su/downloads/ProxyDom-1.0.1.apk',
        ),
        isFalse,
      );
      expect(
        UpdateCheckService.isAllowedDownloadUrl(
          'http://play.google.com/store/apps/details?id=com.proxy.dom',
        ),
        isFalse,
      );
    });

    test('rejects unknown hosts, including the API host', () {
      expect(
        UpdateCheckService.isAllowedDownloadUrl(
          'https://example.com/ProxyDom-1.0.1.apk',
        ),
        isFalse,
      );
      expect(
        UpdateCheckService.isAllowedDownloadUrl(
          'https://api.proxydom.su/downloads/Teremok%20VPN%200.4.26.msi',
        ),
        isFalse,
      );
      expect(
        UpdateCheckService.isAllowedDownloadUrl(
          'https://proxydom.su.evil.example/ProxyDom-1.0.1.apk',
        ),
        isFalse,
      );
    });

    test('rejects a missing URL', () {
      expect(UpdateCheckService.isAllowedDownloadUrl(''), isFalse);
      expect(UpdateCheckService.isAllowedDownloadUrl('   '), isFalse);
    });

    test('rejects userinfo and explicit ports', () {
      expect(
        UpdateCheckService.isAllowedDownloadUrl(
          'https://user@proxydom.su/ProxyDom-1.0.1.apk',
        ),
        isFalse,
      );
      expect(
        UpdateCheckService.isAllowedDownloadUrl(
          'https://proxydom.su:443/ProxyDom-1.0.1.apk',
        ),
        isFalse,
      );
      expect(
        UpdateCheckService.isAllowedDownloadUrl(
          'https://play.google.com:443/store/apps/details?id=com.proxy.dom',
        ),
        isFalse,
      );
    });

    test('keeps the Play page Android-only', () {
      expect(
        UpdateCheckService.isAllowedDownloadUrl(
          _playProxy,
          target: UpdateTarget.windows,
        ),
        isFalse,
      );
      expect(
        UpdateCheckService.isAllowedDownloadUrl(
          _playProxy,
          target: UpdateTarget.ios,
        ),
        isFalse,
      );
    });
  });

  group('UpdateCheckService.shouldPromptUpdate', () {
    test('prompts when the server build is newer and the URL is valid', () {
      expect(
        UpdateCheckService.shouldPromptUpdate(
          localBuildNumber: 21,
          remote: _remote(buildNumber: 22),
          target: UpdateTarget.android,
        ),
        isTrue,
      );
    });

    test('skips when build numbers are equal', () {
      expect(
        UpdateCheckService.shouldPromptUpdate(
          localBuildNumber: 22,
          remote: _remote(buildNumber: 22),
          target: UpdateTarget.android,
        ),
        isFalse,
      );
    });

    test('skips when the local build is newer', () {
      expect(
        UpdateCheckService.shouldPromptUpdate(
          localBuildNumber: 23,
          remote: _remote(buildNumber: 22),
          target: UpdateTarget.android,
        ),
        isFalse,
      );
    });

    test('skips when the download URL is empty', () {
      expect(
        UpdateCheckService.shouldPromptUpdate(
          localBuildNumber: 21,
          remote: _remote(buildNumber: 22, downloadUrl: ''),
          target: UpdateTarget.android,
        ),
        isFalse,
      );
    });

    test('skips when the download URL belongs to Teremok', () {
      expect(
        UpdateCheckService.shouldPromptUpdate(
          localBuildNumber: 21,
          remote: _remote(buildNumber: 22, downloadUrl: _playTeremok),
          target: UpdateTarget.android,
        ),
        isFalse,
      );
    });

    test('accepts the Windows payload when both fields are present', () {
      expect(
        UpdateCheckService.shouldPromptUpdate(
          localBuildNumber: 21,
          remote: _remote(
            buildNumber: 22,
            downloadUrl: '',
            windowsVersion: '1.0.1',
            windowsDownloadUrl: _siteMsi,
          ),
          downloadUrl: _siteMsi,
          target: UpdateTarget.windows,
        ),
        isTrue,
      );
    });
  });

  group('UpdateCheckService.check', () {
    late Dio dio;
    late DioAdapter adapter;
    late UpdateCheckService service;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.test/api/v1/'));
      adapter = DioAdapter(dio: dio);
      service = UpdateCheckService(dio: dio);
    });

    test('returns the selected URL when the server build is newer', () async {
      adapter.onGet(
        '/app/version',
        (server) => server.reply(200, {
          'version': '1.0.1',
          'build_number': 2044,
          'download_url': _playProxy,
          'release_notes': 'Proxy Dom fixes',
        }),
      );

      final result = await service.check(
        localBuildNumber: 2043,
        target: UpdateTarget.android,
      );
      expect(result.shouldPrompt, isTrue);
      expect(result.downloadUrl, _playProxy);
      expect(result.remote?.version, '1.0.1');
      expect(result.remote?.buildNumber, 2044);
    });

    test('does not prompt for the Teremok Play package', () async {
      adapter.onGet(
        '/app/version',
        (server) => server.reply(200, {
          'version': '1.0.0',
          'build_number': 2043,
          'download_url': _playTeremok,
          'release_notes': 'Teremok VPN',
        }),
      );

      final result = await service.check(
        localBuildNumber: 21,
        target: UpdateTarget.android,
      );
      expect(result.shouldPrompt, isFalse);
      expect(result.remote, isNull);
      expect(result.downloadUrl, isNull);
    });

    test('does not prompt for an unknown host', () async {
      adapter.onGet(
        '/app/version',
        (server) => server.reply(200, {
          'version': '1.0.1',
          'build_number': 2044,
          'download_url': 'https://example.com/ProxyDom-1.0.1.apk',
          'release_notes': '',
        }),
      );

      final result = await service.check(
        localBuildNumber: 21,
        target: UpdateTarget.android,
      );
      expect(result.shouldPrompt, isFalse);
      expect(result.remote, isNull);
    });

    test('does not prompt when the platform URL is empty', () async {
      adapter.onGet(
        '/app/version',
        (server) => server.reply(200, {
          'version': '1.0.1',
          'build_number': 2044,
          'download_url': '',
          'release_notes': '',
        }),
      );

      final result = await service.check(
        localBuildNumber: 21,
        target: UpdateTarget.android,
      );
      expect(result.shouldPrompt, isFalse);
      expect(result.remote, isNull);
    });

    test('Windows reads windows_version and windows_download_url', () async {
      adapter.onGet(
        '/app/version',
        (server) => server.reply(200, {
          'version': '1.0.1',
          'build_number': 2044,
          'download_url': _playTeremok,
          'release_notes': 'mobile notes',
          'windows_version': '1.0.1',
          'windows_download_url': _siteMsi,
          'windows_release_notes': 'windows notes',
        }),
      );

      final result = await service.check(
        localBuildNumber: 21,
        target: UpdateTarget.windows,
      );
      expect(result.shouldPrompt, isTrue);
      expect(result.downloadUrl, _siteMsi);
      expect(result.remote?.windowsVersion, '1.0.1');
    });

    test('Windows does not fall back to the Android download_url', () async {
      adapter.onGet(
        '/app/version',
        (server) => server.reply(200, {
          'version': '1.0.1',
          'build_number': 2044,
          'download_url': _apk,
          'release_notes': '',
        }),
      );

      final result = await service.check(
        localBuildNumber: 21,
        target: UpdateTarget.windows,
      );
      expect(result.shouldPrompt, isFalse);
      expect(result.remote, isNull);
    });

    test('Android does not fall back to windows_download_url', () async {
      adapter.onGet(
        '/app/version',
        (server) => server.reply(200, {
          'version': '1.0.1',
          'build_number': 2044,
          'download_url': '',
          'windows_download_url': _siteMsi,
          'release_notes': '',
        }),
      );

      final result = await service.check(
        localBuildNumber: 21,
        target: UpdateTarget.android,
      );
      expect(result.shouldPrompt, isFalse);
      expect(result.remote, isNull);
    });

    test('iOS does not offer an Android Play link', () async {
      adapter.onGet(
        '/app/version',
        (server) => server.reply(200, {
          'version': '1.0.1',
          'build_number': 2044,
          'download_url': _playProxy,
          'release_notes': '',
        }),
      );

      final result = await service.check(
        localBuildNumber: 21,
        target: UpdateTarget.ios,
      );
      expect(result.shouldPrompt, isFalse);
      expect(result.remote, isNull);
    });

    test('is silent on a network error', () async {
      adapter.onGet(
        '/app/version',
        (server) => server.throws(
          500,
          DioException(
            requestOptions: RequestOptions(path: '/app/version'),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
      );

      final result = await service.check(
        localBuildNumber: 21,
        target: UpdateTarget.android,
      );
      expect(result.shouldPrompt, isFalse);
      expect(result.remote, isNull);
    });

    test('is silent on a non-200 response', () async {
      adapter.onGet(
        '/app/version',
        (server) => server.reply(401, {'detail': 'unauthorized'}),
      );

      final result = await service.check(
        localBuildNumber: 21,
        target: UpdateTarget.android,
      );
      expect(result.shouldPrompt, isFalse);
      expect(result.remote, isNull);
    });
  });
}
