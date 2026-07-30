import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/application/locale_provider.dart';
import '../application/auth_provider.dart';
import '../domain/phone_country.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _nationalController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  PhoneCountry _selectedCountry = PhoneCountry.defaultCountry;
  bool _calling = false;
  String? _error;

  @override
  void dispose() {
    _nationalController.dispose();
    super.dispose();
  }

  String _buildE164() {
    final digits = _nationalController.text.replaceAll(RegExp(r'\D'), '');
    return _selectedCountry.toE164(digits);
  }

  String _formatDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return AppL10n.of(context).loginErrorTimeout;
    }
    if (e.type == DioExceptionType.connectionError) {
      return AppL10n.of(context).loginErrorNetwork;
    }
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          return first['msg'].toString();
        }
      }
    }
    return AppL10n.of(context).loginErrorGeneric;
  }

  Future<void> _onCallPressed() async {
    final phone = _buildE164();
    final digits = _nationalController.text.replaceAll(RegExp(r'\D'), '');
    if (!_selectedCountry.isValidNational(digits)) {
      setState(() => _error = AppL10n.of(context).loginPhoneError);
      return;
    }
    setState(() {
      _calling = true;
      _error = null;
    });
    try {
      final resp = await ApiClient.postAuth(
        '/auth/flash-call/request',
        data: {'phone': phone},
      );
      if (!mounted) return;
      if (resp.statusCode == 200 || resp.statusCode == 202) {
        AppRouter.pendingPhone = phone;
        context.go('/verify?phone=${Uri.encodeComponent(phone)}');
      } else {
        setState(() {
          _error = AppL10n.of(context).loginErrorGeneric;
        });
      }
    } on DioException catch (e) {
      setState(() {
        _error = _formatDioError(e);
      });
    } catch (_) {
      setState(() {
        _error = AppL10n.of(context).loginErrorGeneric;
      });
    } finally {
      if (mounted) {
        setState(() {
          _calling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final locale = ref.watch(localeProvider).valueOrNull ??
        Localizations.localeOf(context);
    final isRu = locale.languageCode == 'ru';
    ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.loginTitle),
        actions: [
          TextButton(
            onPressed: () {
              final next = isRu ? const Locale('en') : const Locale('ru');
              ref.read(localeProvider.notifier).setLocale(next);
            },
            child: Text(
              locale.languageCode.toUpperCase(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: DropdownButtonFormField<PhoneCountry>(
                        value: _selectedCountry,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                        ),
                        items: PhoneCountry.zvonokPool
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                  c.displayPrefix,
                                  style: const TextStyle(fontSize: 18),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _calling
                            ? null
                            : (c) {
                                if (c != null) {
                                  setState(() {
                                    _selectedCountry = c;
                                    _error = null;
                                  });
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _nationalController,
                        keyboardType: TextInputType.phone,
                        enabled: !_calling,
                        maxLength: _selectedCountry.nationalDigits,
                        autofocus: true,
                        decoration: InputDecoration(
                          counterText: '',
                          border: const OutlineInputBorder(),
                          errorText: _error,
                        ),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _calling ? null : _onCallPressed,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: _calling
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l.loginCallButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
