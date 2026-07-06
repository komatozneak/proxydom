import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app.dart';
import '../../../core/api_client.dart';
import '../../../core/router.dart';
import '../../../l10n/app_localizations.dart';
import '../application/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneRegex = RegExp(r'^\+7\d{10}$');
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _calling = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDioError(DioException e) {
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
    return e.message ?? 'Network error';
  }

  Future<void> _onCallPressed() async {
    final phone = _controller.text.trim();
    if (!_phoneRegex.hasMatch(phone)) {
      setState(() => _error = '+7XXXXXXXXXX');
      return;
    }
    setState(() {
      _calling = true;
      _error = null;
    });
    try {
      final resp = await ApiClient.instance.post(
        '/auth/flash-call/request',
        data: {'phone': phone},
      );
      if (!mounted) return;
      if (resp.statusCode == 200 || resp.statusCode == 202) {
        AppRouter.pendingPhone = phone;
        context.go('/verify?phone=${Uri.encodeComponent(phone)}');
      } else {
        setState(() {
          _error = 'Не удалось инициировать звонок (HTTP ${resp.statusCode})';
        });
      }
    } on DioException catch (e) {
      setState(() {
        _error = _formatDioError(e);
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
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
    final theme = Theme.of(context);
    // Touch ref so Riverpod считает экран зависимым от auth (для redirect-watch).
    ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.loginTitle),
        actions: [
          TextButton(
            onPressed: () {
              final next = AppLocale.current.languageCode == 'ru'
                  ? const Locale('en')
                  : const Locale('ru');
              AppLocale.set(next);
              (context as Element).findAncestorWidgetOfExactType<MaterialApp>();
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  ),
                ),
              );
              Navigator.of(context).pop();
            },
            child: Text(
              AppLocale.current.languageCode.toUpperCase(),
              style: const TextStyle(color: Colors.white),
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
                Icon(
                  Icons.lock_outline,
                  size: 96,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  l.loginTitle,
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _controller,
                  keyboardType: TextInputType.phone,
                  enabled: !_calling,
                  decoration: InputDecoration(
                    labelText: l.loginPhoneLabel,
                    hintText: l.loginPhoneHint,
                    helperText: l.loginPhoneHelper,
                    prefixIcon: const Icon(Icons.phone),
                    border: const OutlineInputBorder(),
                    errorText: _error,
                  ),
                  validator: (v) {
                    if (v == null || !_phoneRegex.hasMatch(v)) {
                      return l.loginPhoneError;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _calling ? null : _onCallPressed,
                  icon: _calling
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.phone_in_talk),
                  label: Text(_calling ? l.loginCallingTitle : l.loginCallButton),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}