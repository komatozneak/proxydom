import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../config.dart';

/// Platform whose update payload is being read.
enum UpdateTarget { android, ios, windows, other }

/// Maps Flutter's target platform to the update payload selector.
UpdateTarget updateTargetFor(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.android:
      return UpdateTarget.android;
    case TargetPlatform.iOS:
      return UpdateTarget.ios;
    case TargetPlatform.windows:
      return UpdateTarget.windows;
    default:
      return UpdateTarget.other;
  }
}

/// Payload from `GET /api/v1/app/version`.
class AppVersionInfo {
  const AppVersionInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.releaseNotes,
    this.windowsVersion = '',
    this.windowsDownloadUrl = '',
    this.windowsReleaseNotes = '',
  });

  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String releaseNotes;

  /// Windows payload, absent on the Android/iOS fields.
  final String windowsVersion;
  final String windowsDownloadUrl;
  final String windowsReleaseNotes;

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      version: json['version'] as String? ?? '',
      buildNumber: (json['build_number'] as num?)?.toInt() ?? 0,
      downloadUrl: (json['download_url'] as String? ?? '').trim(),
      releaseNotes: json['release_notes'] as String? ?? '',
      windowsVersion: (json['windows_version'] as String? ?? '').trim(),
      windowsDownloadUrl:
          (json['windows_download_url'] as String? ?? '').trim(),
      windowsReleaseNotes: json['windows_release_notes'] as String? ?? '',
    );
  }
}

/// Outcome of comparing local build vs server.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.shouldPrompt,
    this.remote,
    this.downloadUrl,
  });

  final bool shouldPrompt;
  final AppVersionInfo? remote;

  /// Platform URL selected and validated for this check.
  final String? downloadUrl;

  static const none = UpdateCheckResult(shouldPrompt: false);
}

/// Soft update check — no OTA, opens the selected URL in the system browser.
class UpdateCheckService {
  UpdateCheckService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConfig.baseUrl,
                connectTimeout: AppConfig.connectTimeout,
                receiveTimeout: AppConfig.receiveTimeout,
                responseType: ResponseType.json,
                validateStatus: (s) => s != null && s < 500,
              ),
            );

  final Dio _dio;

  static const _playHost = 'play.google.com';
  static const _playPath = '/store/apps/details';
  static const _playPackageId = 'com.proxy.dom';
  static const _proxyDownloadHosts = {'proxydom.su', 'dl.proxydom.su'};

  /// Whether [rawUrl] is a download link this client may open.
  ///
  /// The URL arrives in a remote payload, so it is untrusted: HTTPS only,
  /// exact hosts, no userinfo, no explicit port (even 443). The Play page
  /// must name exactly `com.proxy.dom`; Windows and iOS cannot install an
  /// Android package, so a Play link is Android-only.
  static bool isAllowedDownloadUrl(String rawUrl, {UpdateTarget? target}) {
    final text = rawUrl.trim();
    if (text.isEmpty) return false;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    if (uri.userInfo.isNotEmpty || uri.hasPort) return false;
    // Uri normalizes the default HTTPS port away, so the raw authority is the
    // only place an explicitly written `:443` remains visible.
    final authority =
        text.substring(uri.scheme.length + 3).split(RegExp(r'[/?#]')).first;
    if (authority.contains(':')) return false;

    final host = uri.host.toLowerCase();
    if (host == _playHost) {
      if (target != null && target != UpdateTarget.android) return false;
      final ids = uri.queryParametersAll['id'];
      return uri.path == _playPath &&
          ids != null &&
          ids.length == 1 &&
          ids.single == _playPackageId;
    }
    return _proxyDownloadHosts.contains(host);
  }

  /// Platform-specific download URL, or null when the payload does not
  /// describe an update for [target].
  static String? downloadUrlFor(AppVersionInfo remote, UpdateTarget target) {
    switch (target) {
      case UpdateTarget.android:
      case UpdateTarget.ios:
        return _nonEmpty(remote.downloadUrl);
      case UpdateTarget.windows:
        return _nonEmpty(remote.windowsDownloadUrl);
      case UpdateTarget.other:
        return null;
    }
  }

  /// Pure decision helper (unit-testable).
  ///
  /// [downloadUrl] defaults to the payload's Android/iOS URL. Callers that
  /// know the platform should pass the selected URL and [target] explicitly.
  static bool shouldPromptUpdate({
    required int localBuildNumber,
    required AppVersionInfo remote,
    String? downloadUrl,
    UpdateTarget? target,
  }) {
    final candidate = downloadUrl ?? remote.downloadUrl;
    return remote.buildNumber > localBuildNumber &&
        isAllowedDownloadUrl(candidate, target: target);
  }

  /// Fetches remote version and compares with [localBuildNumber].
  ///
  /// Network, parse and untrusted-URL failures all return
  /// [UpdateCheckResult.none]: an update is never offered from a page this
  /// client cannot prove belongs to Proxy Dom.
  Future<UpdateCheckResult> check({
    required int localBuildNumber,
    UpdateTarget? target,
  }) async {
    final platform = target ?? updateTargetFor(defaultTargetPlatform);
    try {
      // Leading slash required: Dio joins as baseUrl + path (no separator).
      final resp = await _dio.get<Map<String, dynamic>>('/app/version');
      final data = resp.data;
      if (resp.statusCode != 200 || data == null) {
        return UpdateCheckResult.none;
      }
      final remote = AppVersionInfo.fromJson(data);
      final url = downloadUrlFor(remote, platform);
      if (url == null) {
        _debugSkip(platform, 'missing');
        return UpdateCheckResult.none;
      }
      if (!isAllowedDownloadUrl(url, target: platform)) {
        _debugSkip(platform, 'not allowed');
        return UpdateCheckResult.none;
      }
      final prompt = shouldPromptUpdate(
        localBuildNumber: localBuildNumber,
        remote: remote,
        downloadUrl: url,
        target: platform,
      );
      return UpdateCheckResult(
        shouldPrompt: prompt,
        remote: remote,
        downloadUrl: url,
      );
    } catch (_) {
      return UpdateCheckResult.none;
    }
  }

  /// Cold-start entry: PackageInfo → check → optional AlertDialog.
  Future<void> maybePrompt(BuildContext context) async {
    if (!context.mounted) return;
    final info = await PackageInfo.fromPlatform();
    final localBuild = int.tryParse(info.buildNumber) ?? 0;
    final target = updateTargetFor(defaultTargetPlatform);
    final result = await check(localBuildNumber: localBuild, target: target);
    final remote = result.remote;
    final downloadUrl = result.downloadUrl;
    if (!result.shouldPrompt || remote == null || downloadUrl == null) return;
    if (!context.mounted) return;

    final l = AppL10n.of(context);
    final version =
        target == UpdateTarget.windows && remote.windowsVersion.isNotEmpty
            ? remote.windowsVersion
            : remote.version;
    final notes = target == UpdateTarget.windows &&
            remote.windowsReleaseNotes.trim().isNotEmpty
        ? remote.windowsReleaseNotes.trim()
        : remote.releaseNotes.trim();
    final body = notes.isEmpty
        ? l.updateAvailableBody(version)
        : '${l.updateAvailableBody(version)}\n\n$notes';

    final update = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(l.updateAvailableTitle),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.updateLater),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.updateNow),
          ),
        ],
      ),
    );

    if (update != true) return;
    if (!isAllowedDownloadUrl(downloadUrl, target: target)) return;
    final uri = Uri.tryParse(downloadUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String? _nonEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static void _debugSkip(UpdateTarget target, String reason) {
    if (!kDebugMode) return;
    debugPrint(
      'UpdateCheckService: ${target.name} download URL $reason; '
      'update prompt skipped',
    );
  }
}
