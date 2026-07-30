import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:teremok_connect/core/updates/update_check_service.dart';

void main() {
  group('UpdateCheckService.shouldPromptUpdate', () {
    test('prompts when server build is newer and URL present', () {
      const remote = AppVersionInfo(
        version: '0.1.3',
        buildNumber: 2004,
        downloadUrl: 'https://example.com/app.apk',
        releaseNotes: 'fixes',
      );
      expect(
        UpdateCheckService.shouldPromptUpdate(
          localBuildNumber: 2003,
          remote: remote,
        ),
        isTrue,
      );
    });

    test('skips when build numbers are equal', () {
      const remote = AppVersionInfo(
        version: '0.1.2',
        buildNumber: 2003,
        downloadUrl: 'https://example.com/app.apk',
        releaseNotes: '',
      );
      expect(
        UpdateCheckService.shouldPromptUpdate(
          localBuildNumber: 2003,
          remote: remote,
        ),
        isFalse,
      );
    });

    test('skips when download_url is empty', () {
      const remote = AppVersionInfo(
        version: '0.1.3',
        buildNumber: 9999,
        downloadUrl: '',
        releaseNotes: 'notes',
      );
      expect(
        UpdateCheckService.shouldPromptUpdate(
          localBuildNumber: 1,
          remote: remote,
        ),
        isFalse,
      );
    });

    test('skips when local build is newer', () {
      const remote = AppVersionInfo(
        version: '0.1.1',
        buildNumber: 2000,
        downloadUrl: 'https://example.com/app.apk',
        releaseNotes: '',
      );
      expect(
        UpdateCheckService.shouldPromptUpdate(
          localBuildNumber: 2003,
          remote: remote,
        ),
        isFalse,
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

    test('returns shouldPrompt when server is newer', () async {
      adapter.onGet(
        '/app/version',
        (server) => server.reply(200, {
          'version': '0.1.3',
          'build_number': 2004,
          'download_url': 'https://example.com/app.apk',
          'release_notes': 'VPN fixes',
        }),
      );

      final result = await service.check(localBuildNumber: 2003);
      expect(result.shouldPrompt, isTrue);
      expect(result.remote?.version, '0.1.3');
      expect(result.remote?.buildNumber, 2004);
    });

    test('skips prompt when download_url empty', () async {
      adapter.onGet(
        '/app/version',
        (server) => server.reply(200, {
          'version': '0.1.3',
          'build_number': 2004,
          'download_url': '',
          'release_notes': '',
        }),
      );

      final result = await service.check(localBuildNumber: 2003);
      expect(result.shouldPrompt, isFalse);
    });

    test('silent on network error', () async {
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

      final result = await service.check(localBuildNumber: 2003);
      expect(result.shouldPrompt, isFalse);
      expect(result.remote, isNull);
    });
  });
}
