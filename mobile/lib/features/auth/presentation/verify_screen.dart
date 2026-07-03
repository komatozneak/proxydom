import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/router.dart';
import '../../../core/token_storage.dart';
import '../../../l10n/app_localizations.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, required this.phone});

  /// Телефон приходит из query parameter /verify?phone=...
  final String phone;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
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
      await ApiClient.instance.post(
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
      final resp = await ApiClient.instance.post(
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
          AppRouter.setAuthenticated(true);
          AppRouter.setPendingPhone(null);
          if (!mounted) return;
          context.go('/home');
          return;
        }
      }

      setState(() {
        _error = 'Неверный код (HTTP ${resp.statusCode})';
        for (final c in _controllers) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
      });
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['detail']?.toString() ??
            e.message ??
            'Network error';
        for (final c in _controllers) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _verifying = false;
        });
      }
    }
  }

  void _onDigitInput(int index, String value) {
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
    final theme = Theme.of(context);
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
              const SizedBox(height: 24),
              const Icon(Icons.dialpad, size: 96),
              const SizedBox(height: 16),
              Text(
                l.verifySentTo(widget.phone),
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  4,
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: SizedBox(
                      width: 56,
                      height: 64,
                      child: TextField(
                        controller: _controllers[i],
                        focusNode: _focusNodes[i],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        style: theme.textTheme.headlineMedium,
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
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.red)),
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
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Text(
                  'TEST MODE: Звонок от Zvonok не приходит, потому что у нас нет живого key. '
                  'Для проверки флоу создай юзера через SQL и используй код 0000.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
              TextButton(
                onPressed: _verifying
                    ? null
                    : () {
                        for (var i = 0; i < 4; i++) {
                          _controllers[i].text = '0';
                        }
                        _focusNodes[3].unfocus();
                        _onCodeComplete();
                      },
                child: const Text('Force submit "0000"'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}