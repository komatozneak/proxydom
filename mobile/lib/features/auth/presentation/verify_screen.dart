import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/router.dart';
import '../../../core/token_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../application/auth_provider.dart';

class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key, required this.phone});

  /// Телефон приходит из query parameter /verify?phone=...
  final String phone;

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final List<TextEditingController> _controllers = List.generate(
    4,
    (i) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(4, (i) => FocusNode());

  bool _verifying = false;
  bool _allowResend = false;
  int _resendCooldown = 30;
  String? _error;

  /// Активный cooldown-таймер — отменяем в dispose, чтобы тесты не висели.
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _startResendCooldown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startResendCooldown() {
    _cooldownTimer?.cancel();
    var i = 30;
    setState(() {
      _resendCooldown = i;
      _allowResend = false;
    });
    _cooldownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        i -= 1;
        if (i <= 0) {
          timer.cancel();
          setState(() {
            _allowResend = true;
          });
        } else {
          setState(() {
            _resendCooldown = i;
          });
        }
      },
    );
  }

  Future<void> _onResend() async {
    if (!_allowResend) return;
    setState(() {
      _error = null;
    });
    try {
      await ApiClient.postAuth(
        '/auth/flash-call/request',
        data: {'phone': widget.phone},
      );
      if (!mounted) return;
      _resendCooldown = 30;
      setState(() {
        _allowResend = false;
      });
      _startResendCooldown();
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['detail']?.toString() ?? 'Network error';
      });
    }
  }

  String _getCode() => _controllers.map((c) => c.text).join();

  Future<void> _onCodeComplete() async {
    final code = _getCode();
    if (code.length != 4) return;
    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final resp = await ApiClient.postAuth(
        '/auth/flash-call/verify',
        data: {'phone': widget.phone, 'last_4': code},
      );

      if (resp.statusCode == 200 && resp.data is Map) {
        final data = resp.data as Map;
        final access = data['access_token'] as String?;
        final refresh = data['refresh_token'] as String?;
        if (access != null && refresh != null) {
          await TokenStorage.instance.saveTokens(
            accessToken: access,
            refreshToken: refresh,
          );
          AppRouter.pendingPhone = null;
          if (!mounted) return;
          // Пишем в authProvider — GoRouter сам перенаправит на /home.
          await ref.read(authProvider.notifier).authenticated(
                accessToken: access,
                refreshToken: refresh,
              );
          return;
        }
      }

      setState(() {
        _error = AppL10n.of(context).verifyWrongCode;
        for (final c in _controllers) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
      });
    } on DioException catch (e) {
      final detail = e.response?.data;
      final msg = detail is Map ? detail['detail']?.toString() : null;
      setState(() {
        _error = msg ?? AppL10n.of(context).verifyWrongCode;
        for (final c in _controllers) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
      });
    } catch (_) {
      setState(() {
        _error = AppL10n.of(context).verifyWrongCode;
      });
    } finally {
      if (mounted) {
        setState(() {
          _verifying = false;
        });
      }
    }
  }

  void _onBackspace(int index) {
    if (_controllers[index].text.isNotEmpty) {
      _controllers[index].clear();
      return;
    }
    if (index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
    }
  }

  KeyEventResult _handleKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _onBackspace(index);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onDigitInput(int index, String value) {
    if (value.isEmpty) {
      _onBackspace(index);
      return;
    }
    if (value.length > 1) {
      if (value.length == 4 && RegExp(r'^\d{4}$').hasMatch(value)) {
        for (var i = 0; i < 4; i++) {
          _controllers[i].text = value[i];
        }
        _focusNodes[3].unfocus();
        _onCodeComplete();
        return;
      }
      _controllers[index].text = value[value.length - 1];
    }
    if (_controllers[index].text.isNotEmpty && index < 3) {
      _focusNodes[index + 1].requestFocus();
    }
    if (_getCode().length == 4 && !_verifying) {
      _onCodeComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.verifyTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  4,
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: SizedBox(
                      width: 56,
                      height: 64,
                      child: Focus(
                      onKeyEvent: (node, event) => _handleKeyEvent(i, event),
                      child: TextField(
                        controller: _controllers[i],
                        focusNode: _focusNodes[i],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        style: Theme.of(context).textTheme.headlineMedium,
                        decoration: InputDecoration(
                          counterText: '',
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (v) => _onDigitInput(i, v),
                        onSubmitted: (_) {
                          if (i < 3) _focusNodes[i + 1].requestFocus();
                        },
                      ),
                    ),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              if (_verifying) ...[
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
              ],
              const SizedBox(height: 24),
              TextButton(
                onPressed: _allowResend ? _onResend : null,
                child: Text(
                  _allowResend
                      ? l.verifyResend
                      : l.verifyResendIn(_resendCooldown),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}