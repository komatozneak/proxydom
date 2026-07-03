import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app.dart';
import '../../../../core/api_client.dart';
import '../../../../core/router.dart';
import '../../../../l10n/app_localizations.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static final _phoneRegex = RegExp(r'^\+7\d{10}$');
  final _controller = TextEditingController(text: '+7');
  final _formKey = GlobalKey<FormState>();
  bool _calling = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onCallPressed() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _calling = true;
      _error = null;
    });

    final phone = _controller.text.trim();
    try {
      final resp = await ApiClient.instance.post(
        '/auth/flash-call/request',
        data: {'phone': phone},
      );
      if (resp.statusCode == 202 || resp.statusCode == 200) {
        AppRouter.setPendingPhone(phone);
        if (!mounted) return;
        context.go('/verify?phone=${Uri.encodeComponent(phone)}');
      } else {
        setState(() {
          _error = 'Не удалось инициировать звонок (${resp.statusCode})';
        });
      }
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['detail']?.toString() ??
            e.message ??
            'Network error';
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
              // force rebuild через смену key в MaterialApp — упрощённый способ
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 96),
                  const SizedBox(height: 24),
                  Text(
                    l.loginTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _controller,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: l.loginPhoneLabel,
                      hintText: l.loginPhoneHint,
                      helperText: l.loginPhoneHelper,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.phone),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return l.loginPhoneError;
                      if (!_phoneRegex.hasMatch(v.trim())) return l.loginPhoneError;
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _calling ? null : _onCallPressed,
                      icon: _calling
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.phone_in_talk),
                      label: Text(
                        _calling ? l.loginCallingTitle : l.loginCallButton,
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}