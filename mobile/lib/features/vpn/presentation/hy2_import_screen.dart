import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/diagnostics/ui_log.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../core/widgets/proxydom_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../../home/application/vpn_status.dart';
import '../data/hy2_import_store.dart';
import '../data/route_document.dart';
import '../data/share_link_parser.dart';
import '../data/subscription_device.dart';
import '../data/subscription_label.dart';
import '../data/subscription_link_inbox.dart';
import 'free_client_chrome.dart';
import 'server_instrument_parts.dart';
import 'windows_share_qr.dart';

/// Add a link or key, preview the profiles, then save or connect.
class Hy2ImportScreen extends ConsumerStatefulWidget {
  const Hy2ImportScreen({super.key});

  @override
  ConsumerState<Hy2ImportScreen> createState() => _Hy2ImportScreenState();
}

class _Hy2ImportScreenState extends ConsumerState<Hy2ImportScreen> {
  final _controller = TextEditingController();
  final _fieldFocus = FocusNode();
  List<ParsedShareLink> _preview = const [];
  String? _previewTitle;
  String? _error;
  bool _busy = false;
  bool _loadingPreview = false;
  bool _subscriptionUrl = false;
  bool _hasSaved = false;
  var _clipboardApplied = false;
  int _previewGen = 0;

  @override
  void initState() {
    super.initState();
    Hy2ImportStore.instance.load().then((links) {
      if (!mounted) return;
      setState(() => _hasSaved = links.isNotEmpty);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pending = SubscriptionLinkInbox.take();
    if (pending != null && pending.isNotEmpty) {
      _clipboardApplied = true;
      _controller.text = pending;
      _previewInput(pending);
      return;
    }
    if (_clipboardApplied) return;
    final paste =
        GoRouterState.of(context).uri.queryParameters['clipboard'] == '1';
    if (!paste) return;
    _clipboardApplied = true;
    _pasteClipboard();
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    UiLog.action(
      'import',
      'paste',
      result: text.isEmpty ? 'empty' : 'ok',
      extra: {'chars': text.length},
    );
    if (!mounted || text.isEmpty) return;
    _controller.text = text;
    _previewInput(text);
  }

  void _previewInput(String raw) {
    final text = raw.trim();
    final gen = ++_previewGen;
    if (isPendingSubscriptionUrl(text)) {
      setState(() {
        _subscriptionUrl = true;
        _loadingPreview = true;
        _error = null;
        _preview = const [];
        _previewTitle = null;
      });
      Hy2ImportStore.instance.previewSubscription(text).then((result) {
        if (!mounted || gen != _previewGen) return;
        setState(() {
          _loadingPreview = false;
          _preview = result.links;
          _previewTitle = result.title;
          _error = result.links.isEmpty
              ? 'empty'
              : switch (shareImportDial(
                  result.links,
                  fromDocument: true,
                )) {
                  ShareImportDial.noneHy2 => 'no_hy2',
                  ShareImportDial.singleUnsupported => 'hy2_only',
                  ShareImportDial.hasHy2 => null,
                };
        });
      }).catchError((Object error) {
        if (!mounted || gen != _previewGen) return;
        UiLog.action(
          'import',
          'preview',
          result: 'fail',
          reason: error.runtimeType.toString(),
        );
        setState(() {
          _loadingPreview = false;
          _preview = const [];
          _previewTitle = null;
          _error = switch (error) {
            SubscriptionDocumentException(:final code) => code,
            DocumentSyncException(:final decision)
                when decision == DocumentSyncDecision.drop =>
              'missing',
            _ => 'load',
          };
        });
      });
      return;
    }
    setState(() {
      _subscriptionUrl = false;
      _loadingPreview = false;
      _previewTitle = null;
    });
    try {
      final links = parseShareSubscription(text);
      final dial = shareImportDial(links, fromDocument: false);
      setState(() {
        _preview = links;
        _error = text.isEmpty
            ? null
            : links.isEmpty
                ? 'empty'
                : switch (dial) {
                    ShareImportDial.singleUnsupported => 'hy2_only',
                    ShareImportDial.noneHy2 => 'no_hy2',
                    ShareImportDial.hasHy2 => null,
                  };
      });
    } on FormatException {
      UiLog.action('import', 'preview', result: 'bad');
      setState(() {
        _preview = const [];
        _error = 'bad';
      });
    }
  }

  Future<void> _stopLiveTunnel({required String reason}) async {
    final status = ref.read(vpnProvider);
    if (status is! VpnConnected && status is! VpnConnecting) return;
    await ref.read(vpnProvider.notifier).disconnect(reason: reason);
  }

  bool get _canSave =>
      !_busy &&
      !_loadingPreview &&
      (_error == null || _error == 'no_hy2') &&
      (_subscriptionUrl || _preview.isNotEmpty);

  /// Saves the draft and dials it.
  ///
  /// There was a second path here - save without connecting - and it was the
  /// same question asked with two answers. One key now: save, then go where the
  /// person can act. If nothing in the draft can dial, the key was dead before
  /// they got here and step 2 said so.
  Future<void> _save() async {
    UiLog.action('import', 'save', extra: {'connect': true});
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final links = await Hy2ImportStore.instance.saveInput(_controller.text);
      if (!mounted) return;
      UiLog.action(
        'import',
        'save',
        result: 'ok',
        extra: {'links': links.length, 'connect': true},
      );
      showProxyDomSnackBar(context, AppL10n.of(context).freeServerAdded);
      if (links.isEmpty) {
        context.go('/locations');
        return;
      }
      await _stopLiveTunnel(reason: 'import');
      if (!mounted) return;
      final canStart = links.any(
        (link) => canDialScheme(link.scheme, ios: false),
      );
      context.go(canStart ? '/home' : '/locations');
      return;
    } on SubscriptionDocumentException catch (error) {
      if (!mounted) return;
      UiLog.action('import', 'save', result: 'bad', reason: error.code);
      setState(() {
        _busy = false;
        _error = error.code;
      });
    } on FormatException {
      if (!mounted) return;
      UiLog.action('import', 'save', result: 'bad');
      setState(() {
        _busy = false;
        _error = 'bad';
      });
    } catch (error) {
      if (!mounted) return;
      UiLog.action(
        'import',
        'save',
        result: 'fail',
        reason: error.runtimeType.toString(),
      );
      setState(() {
        _busy = false;
        _error = 'bad';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;

    // A link and its result are one thing, so they are one column in one
    // measure. On a phone that is the whole width; in a window it is 640px,
    // because a link field stretched across 1400px is the phone layout wearing
    // a big coat.
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: _hasSaved
            ? IconButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
                icon: const _AddBackMark(),
              )
            : null,
        title: Text(l.freeAddTitle),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        // Step 1 — the link.
                        AppSurface(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _StepLabel('1', l.freeStepLink),
                              const SizedBox(height: 12),
                              Container(
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.045),
                                  borderRadius:
                                      BorderRadius.circular(AppBrand.radiusCard),
                                  border: Border.all(
                                    color: _fieldFocus.hasFocus
                                        ? AppBrand.mascotGold
                                            .withValues(alpha: 0.75)
                                        : theme.colorScheme.outline
                                            .withValues(alpha: 0.6),
                                    width: _fieldFocus.hasFocus ? 1.6 : 1,
                                  ),
                                ),
                                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                                child: TextField(
                                  controller: _controller,
                                  focusNode: _fieldFocus,
                                  minLines: keyboard ? 2 : 1,
                                  maxLines: keyboard ? 3 : 4,
                                  onChanged: _previewInput,
                                  cursorColor: AppBrand.mascotGold,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'JetBrainsMono',
                                    fontFamilyFallback: const ['Onest'],
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: l.freeAddHint,
                                    hintStyle: theme.textTheme.bodyMedium
                                        ?.copyWith(
                                      color: mute.withValues(alpha: 0.6),
                                      fontFamily: 'JetBrainsMono',
                                      fontFamilyFallback: const ['Onest'],
                                      fontSize: 13.5,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    suffixIcon: _controller.text.isEmpty
                                        ? null
                                        : IconButton(
                                            onPressed: () {
                                              _controller.clear();
                                              _previewInput('');
                                            },
                                            icon: const AppIcon(
                                              AppIcons.x,
                                              size: 18,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              FreeClientActionBar(
                                draft: true,
                                onPaste: _pasteClipboard,
                                onScan: () {
                                  UiLog.action('import', 'scan');
                                  openFreeClientCapture(context);
                                },
                              ),
                              if (_loadingPreview) ...[
                                const SizedBox(height: 12),
                                const SizedBox(
                                  height: 2,
                                  child: LinearProgressIndicator(
                                    color: AppBrand.mascotGold,
                                    backgroundColor: Colors.transparent,
                                  ),
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                _ErrorLine(_errorFor(l)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Step 2 — what the link actually brought in.
                        AppSurface(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  _StepLabel('2', l.freeStepFound),
                                  const Spacer(),
                                  if (_preview.isNotEmpty)
                                    Text(
                                      '${_preview.length}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        letterSpacing: 1,
                                        fontWeight: FontWeight.w700,
                                        color: AppBrand.mascotGoldLit,
                                      ),
                                    ),
                                ],
                              ),
                              if (_previewTitle != null &&
                                  _previewTitle!.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  _previewTitle!.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              if (_loadingPreview)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 18),
                                  child: Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppBrand.mascotGold,
                                      ),
                                    ),
                                  ),
                                )
                              else if (_error != null &&
                                  _error != 'no_hy2' &&
                                  _error != 'hy2_only')
                                _EmptyPreview(l.freeFieldEmpty)
                              else if (_preview.isEmpty)
                                _EmptyPreview(l.freeEmptyBody)
                              else
                                for (var i = 0; i < _preview.length; i++) ...[
                                  if (i > 0) const SizedBox(height: 7),
                                  Builder(
                                    builder: (context) {
                                      final label =
                                          labelForShareLink(_preview[i]);
                                      final dialable = canDialScheme(
                                        _preview[i].scheme,
                                        ios: false,
                                      );
                                      return NodeLine(
                                        label: label,
                                        endpoint: dialable
                                            ? (label.subtitle.isEmpty
                                                ? _preview[i].endpoint
                                                : label.subtitle)
                                            : l.freeSchemeParked,
                                        selected: false,
                                        onTap: () {},
                                      );
                                    },
                                  ),
                                ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Two keys, in the app's own key language, primary first.
                  // One key. «Сохранить» and «Только сохранить» asked the same question with
                  // two answers, and a person who cannot tell them apart
                  // guesses. The key saves and dials; if the link has nothing
                  // dialable in it, the key stays dead and the second step
                  // says why. It is not stretched: a button across the whole
                  // measure is a banner, not a key.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppActionButton(
                      onPressed: _canSave ? () => _save() : null,
                      icon: AppIcons.check,
                      label: l.freeSaveConnect,
                      color: AppBrand.mascotGold,
                      height: 50,
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

  String _errorFor(AppL10n l) => switch (_error) {
        'load' => l.freeSubscriptionLoadFail,
        'missing' => l.freeSubscriptionMissing,
        'device_limit' => l.freeSubscriptionDeviceLimit,
        'client_refused' => l.freeSubscriptionClientRefused,
        'hy2_only' => l.freeHy2OnlyAdd,
        'no_hy2' => l.freeNoHy2Lines,
        _ => l.freeLinkInvalid,
      };
}

/// `1 · ССЫЛКА` — the step, in the terminal voice the home head uses.
class _StepLabel extends StatelessWidget {
  const _StepLabel(this.step, this.text);

  final String step;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;
    final rule = Container(height: 1, color: mute.withValues(alpha: 0.16));
    return LayoutBuilder(
      builder: (context, box) => Row(
      children: [
        Container(
          width: 16,
          height: 16,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AppBrand.mascotGold.withValues(alpha: 0.7),
            ),
          ),
          child: Text(
            step,
            style: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: AppBrand.mascotGoldLit,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 2.2,
            fontWeight: FontWeight.w700,
            color: mute,
          ),
        ),
        const SizedBox(width: 10),
        // The rule fills what is left, but only where "what is left" exists:
        // a Row with Expanded under an unbounded width throws, and this label
        // is also measured inside unbounded probes.
        if (box.hasBoundedWidth) Expanded(child: rule) else rule,
      ],
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8),
            width: 2.5,
          ),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: mute.withValues(alpha: 0.8),
          fontSize: 13.5,
        ),
      ),
    );
  }
}

class _AddBackMark extends StatelessWidget {
  const _AddBackMark();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color:
            dark ? AppBrand.surfaceVariantDark : AppBrand.surfaceElevatedLight,
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: AppIcon(
        AppIcons.back,
        size: 18,
        color: dark ? AppBrand.inkDark : AppBrand.inkLight,
      ),
    );
  }
}