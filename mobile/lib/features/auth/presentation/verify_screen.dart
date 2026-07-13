import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/router.dart';
import '../../../core/token_storage.dart';
import '../../../core/widgets/app_icon.dart';
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
  /// One field — soft-keyboard backspace works across all digits.
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

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
    _codeController.addListener(_onCodeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _codeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    _codeFocus.dispose();
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
      _codeController.clear();
      _codeFocus.requestFocus();
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['detail']?.toString() ?? 'Network error';
      });
    }
  }

  String get _code => _codeController.text;

  void _onCodeChanged() {
    final digits = _codeController.text.replaceAll(RegExp(r'\D'), '');
    if (digits != _codeController.text) {
      _codeController.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
      return;
    }
    setState(() {});
    if (digits.length == 4 && !_verifying) {
      _onCodeComplete();
    }
  }

  Future<void> _onCodeComplete() async {
    final code = _code;
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
          await ref.read(authProvider.notifier).authenticated(
                accessToken: access,
                refreshToken: refresh,
              );
          return;
        }
      }

      setState(() {
        _error = AppL10n.of(context).verifyWrongCode;
        _codeController.clear();
        _codeFocus.requestFocus();
      });
    } on DioException catch (e) {
      final detail = e.response?.data;
      final msg = detail is Map ? detail['detail']?.toString() : null;
      setState(() {
        _error = msg ?? AppL10n.of(context).verifyWrongCode;
        _codeController.clear();
        _codeFocus.requestFocus();
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

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final code = _code;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.verifyTitle),
        leading: IconButton(
          icon: const AppIcon(AppIcons.back),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 48),
              // Visual 4 boxes; one real TextField underneath for IME backspace.
              Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final filled = i < code.length;
                      final focused = _codeFocus.hasFocus &&
                          (code.length == i ||
                              (code.length == 4 && i == 3));
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 56,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: focused
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                              width: focused ? 2 : 1.5,
                            ),
                          ),
                          child: Text(
                            filled ? code[i] : '',
                            style: theme.textTheme.headlineMedium,
                          ),
                        ),
                      );
                    }),
                  ),
                  Opacity(
                    opacity: 0.01,
                    child: SizedBox(
                      width: 56 * 4 + 12 * 3,
                      height: 64,
                      child: TextField(
                        controller: _codeController,
                        focusNode: _codeFocus,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        maxLength: 4,
                        showCursor: false,
                        enableInteractiveSelection: false,
                        style: const TextStyle(color: Colors.transparent),
                        decoration: const InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        onTap: () => _codeFocus.requestFocus(),
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
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
