import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../config.dart';

/// Payload from `GET /api/v1/app/version`.
class AppVersionInfo {
  const AppVersionInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.releaseNotes,
  });

  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String releaseNotes;

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      version: json['version'] as String? ?? '',
      buildNumber: (json['build_number'] as num?)?.toInt() ?? 0,
      downloadUrl: (json['download_url'] as String? ?? '').trim(),
      releaseNotes: json['release_notes'] as String? ?? '',
    );
  }
}

/// Outcome of comparing local build vs server.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.shouldPrompt,
    this.remote,
  });

  final bool shouldPrompt;
  final AppVersionInfo? remote;

  static const none = UpdateCheckResult(shouldPrompt: false);
}

/// Soft update check — no OTA, opens [downloadUrl] in the system browser.
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

  /// Pure decision helper (unit-testable).
  static bool shouldPromptUpdate({
    required int localBuildNumber,
    required AppVersionInfo remote,
  }) {
    if (remote.downloadUrl.isEmpty) return false;
    return remote.buildNumber > localBuildNumber;
  }

  /// Fetches remote version and compares with [localBuildNumber].
  /// Network / parse failures → [UpdateCheckResult.none] (silent).
  Future<UpdateCheckResult> check({required int localBuildNumber}) async {
    try {
      // Leading slash required: Dio joins as baseUrl + path (no separator).
      final resp = await _dio.get<Map<String, dynamic>>('/app/version');
      final data = resp.data;
      if (resp.statusCode != 200 || data == null) {
        return UpdateCheckResult.none;
      }
      final remote = AppVersionInfo.fromJson(data);
      final prompt = shouldPromptUpdate(
        localBuildNumber: localBuildNumber,
        remote: remote,
      );
      return UpdateCheckResult(shouldPrompt: prompt, remote: remote);
    } catch (_) {
      return UpdateCheckResult.none;
    }
  }

  /// Cold-start entry: PackageInfo → check → optional AlertDialog.
  Future<void> maybePrompt(BuildContext context) async {
    if (!context.mounted) return;
    final info = await PackageInfo.fromPlatform();
    final localBuild = int.tryParse(info.buildNumber) ?? 0;
    final result = await check(localBuildNumber: localBuild);
    if (!result.shouldPrompt || result.remote == null) return;
    if (!context.mounted) return;

    final remote = result.remote!;
    final l = AppL10n.of(context);
    final notes = remote.releaseNotes.trim();
    final body = notes.isEmpty
        ? l.updateAvailableBody(remote.version)
        : '${l.updateAvailableBody(remote.version)}\n\n$notes';

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
    final uri = Uri.tryParse(remote.downloadUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
