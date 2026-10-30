import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/diagnostics/ui_log.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/toasts/proxy_dom_toast.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/proxydom_ground.dart';
import '../../../core/widgets/app_surface.dart';

import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../../home/application/vpn_status.dart';
import '../data/dial_set.dart';
import '../data/hy2_import_store.dart';
import '../data/hy2_link_parser.dart';
import '../data/route_document.dart';
import '../data/share_link_parser.dart';
import '../data/subscription_device.dart';
import '../data/subscription_label.dart';
import '../data/subscription_link_inbox.dart';
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
  List<ShareLineSkip> _skipped = const [];
  String? _previewTitle;
  String? _error;
  bool _busy = false;
  bool _loadingPreview = false;
  bool _subscriptionUrl = false;
  bool _hasSaved = false;
  var _clipboardApplied = false;
  int _previewGen = 0;

  /// Pending subscription fetch. Typing a URL used to fetch on every keystroke:
  /// one request and one DNS lookup per character, each logged as a `doc.fetch`
  /// failure for a host that could not exist yet.
  Timer? _previewDebounce;

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
      final shown = _extractUrl(pending);
      _controller.text = shown;
      _previewInput(shown, immediate: true);
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
    _previewDebounce?.cancel();
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
    final shown = _extractUrl(text);
    _controller.text = shown;
    _previewInput(shown, immediate: true);
  }

  /// The field shows the document address, not the `proxydom://import/` wrapper.
  /// [Hy2ImportStore.saveInput] re-parses whatever the field holds, so the
  /// nested https address is enough; a plain key stays untouched.
  String _extractUrl(String raw) {
    try {
      return subscriptionDocumentTarget(raw)?.url ?? raw;
    } on FormatException {
      return raw;
    }
  }

  void _previewInput(String raw, {bool immediate = false}) {
    final text = raw.trim();
    final gen = ++_previewGen;
    _previewDebounce?.cancel();
    if (isPendingSubscriptionUrl(text)) {
      setState(() {
        _subscriptionUrl = true;
        _loadingPreview = true;
        _error = null;
        _preview = const [];
        _skipped = const [];
        _previewTitle = null;
      });
      // Paste and deep links arrive complete, so they fetch at once. A typed
      // URL waits until the edits stop; otherwise every character issues a
      // request and a DNS lookup for a host that is still being spelled.
      if (immediate) {
        _fetchSubscriptionPreview(text, gen);
      } else {
        _previewDebounce = Timer(
          const Duration(milliseconds: 900),
          () => _fetchSubscriptionPreview(text, gen),
        );
      }
      return;
    }
    setState(() {
      _subscriptionUrl = false;
      _loadingPreview = false;
      _previewTitle = null;
    });
    try {
      final report = inspectShareSubscription(text);
      final links = report.links;
      final dial = shareImportDial(links, fromDocument: false);
      setState(() {
        _preview = links;
        _skipped = report.skipped;
        _error = text.isEmpty
            ? null
            : links.isEmpty && report.skipped.isNotEmpty
                ? null
                : links.isEmpty
                    ? 'empty'
                    : switch (dial) {
                        ShareImportDial.singleUnsupported => 'hy2_only',
                        ShareImportDial.noneDialable => 'no_hy2',
                        ShareImportDial.dialable => null,
                      };
      });
    } on FormatException {
      UiLog.action('import', 'preview', result: 'bad');
      setState(() {
        _preview = const [];
        _skipped = const [];
        _error = 'bad';
      });
    }
  }

  /// Fetches and previews a subscription document. [gen] drops an answer that
  /// belongs to an edit the field has already moved past.
  void _fetchSubscriptionPreview(String text, int gen) {
    Hy2ImportStore.instance.previewSubscription(text).then((result) {
      if (!mounted || gen != _previewGen) return;
      setState(() {
        _loadingPreview = false;
        _preview = result.links;
        _skipped = result.skipped;
        _previewTitle = result.title;
        _error = result.links.isEmpty && result.skipped.isEmpty
            ? 'empty'
            : result.links.isEmpty
                ? null
                : switch (shareImportDial(
                    result.links,
                    fromDocument: true,
                  )) {
                    ShareImportDial.noneDialable => 'no_hy2',
                    ShareImportDial.singleUnsupported => 'hy2_only',
                    ShareImportDial.dialable => null,
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
      (_subscriptionUrl || _preview.isNotEmpty || _skipped.isNotEmpty);

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  /// Saves the draft and dials it.
  ///
  /// There was a second path here - save without connecting - and it was the
  /// same question asked with two answers. One key now: save, then go where the
  /// person can act. If nothing in the draft can dial, the key was dead before
  /// they got here and step 2 said so.
  Future<void> _save() async {
    // A second press while the first is in flight used to start a second save
    // over the same draft. The button is disabled while busy, but the keyboard
    // and a double tap can both reach this method before the frame redraws.
    if (_busy) return;
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
      showProxyDomToast(
        AppL10n.of(context).freeServerAdded,
        tone: ToastTone.success,
      );
      if (links.isEmpty) {
        context.go('/locations');
        return;
      }
      await _stopLiveTunnel(reason: 'import');
      if (!mounted) return;
      final canStart = links.any(canDialLink);
      context.go(canStart ? '/home' : '/locations');
      return;
    } on SubscriptionDocumentException catch (error) {
      if (!mounted) return;
      UiLog.action('import', 'save', result: 'bad', reason: error.code);
      setState(() {
        _error = error.code;
      });
    } on FormatException {
      if (!mounted) return;
      UiLog.action('import', 'save', result: 'bad');
      setState(() {
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
        _error = 'bad';
      });
    } finally {
      // The button must come back even when the save ended without a
      // navigation — a no-op `go`, an early return, or an exception the
      // handlers do not name. Leaving `_busy` true is a screen whose only
      // action is permanently dead while its button still looks enabled,
      // which is exactly how it read on a phone.
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;

    if (windowsDesktop) {
      return _WindowsAddScreen(
        controller: _controller,
        focusNode: _fieldFocus,
        onChanged: _previewInput,
        onPaste: _pasteClipboard,
        onClear: () {
          _controller.clear();
          _previewInput('');
        },
        onBack: _goBack,
        onSave: _canSave ? () => _save() : null,
        loading: _loadingPreview,
        errorText: _error == null ? null : _errorFor(l),
        unsupportedText: _skipped.isEmpty
            ? null
            : formatUnsupportedImport(
                countLine: l.freeImportCount(_preview.length, _skipped.length),
                skipped: _skipped,
              ),
        previewTitle: _previewTitle,
        preview: _preview,
      );
    }

    // A link and its result are one thing, so they are one column in one
    // measure. On a phone that is the whole width; in a window it is 640px,
    // because a link field stretched across 1400px is the phone layout wearing
    // a big coat.
    return NightBackdrop(
      child: Scaffold(
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
                                    borderRadius: BorderRadius.circular(
                                        AppBrand.radiusCard),
                                    border: Border.all(
                                      color: _fieldFocus.hasFocus
                                          ? AppBrand.mascotGold
                                              .withValues(alpha: 0.75)
                                          : theme.colorScheme.outline
                                              .withValues(alpha: 0.6),
                                      width: _fieldFocus.hasFocus ? 1.6 : 1,
                                    ),
                                  ),
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 6, 6, 6),
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _fieldFocus,
                                    minLines: 1,
                                    maxLines: 1,
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
                                      hintStyle:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: mute.withValues(alpha: 0.6),
                                        fontFamily: 'JetBrainsMono',
                                        fontFamilyFallback: const ['Onest'],
                                        fontSize: 13.5,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 12),
                                      // Paste and scan live in the field: they
                                      // are input methods, not peer actions next
                                      // to it.
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: l.freePaste,
                                            onPressed: _pasteClipboard,
                                            icon: const AppIcon(
                                              AppIcons.clipboard,
                                              size: 18,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: l.freeQr,
                                            onPressed: () {
                                              UiLog.action('import', 'scan');
                                              openFreeClientCapture(context);
                                            },
                                            icon: const AppIcon(
                                              AppIcons.qrCode,
                                              size: 18,
                                            ),
                                          ),
                                          if (_controller.text.isNotEmpty)
                                            IconButton(
                                              onPressed: () {
                                                _controller.clear();
                                                _previewInput('');
                                              },
                                              icon: const AppIcon(
                                                AppIcons.x,
                                                size: 18,
                                              ),
                                            ),
                                        ],
                                      ),
                                      suffixIconConstraints:
                                          const BoxConstraints(
                                        minHeight: 48,
                                        minWidth: 48,
                                      ),
                                    ),
                                  ),
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
                                if (_skipped.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    formatUnsupportedImport(
                                      countLine: l.freeImportCount(
                                        _preview.length,
                                        _skipped.length,
                                      ),
                                      skipped: _skipped,
                                    ),
                                    style: TextStyle(
                                      color: mute,
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
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
                                    // The same ruled line the servers tab draws:
                                    // this is the same list, one step before it is
                                    // saved, so it has to look like itself.
                                    if (i > 0) const NodeRule(),
                                    Builder(
                                      builder: (context) {
                                        final label =
                                            labelForShareLink(_preview[i]);
                                        final dialable = canDialLink(
                                          _preview[i],
                                        );
                                        return NodeLine(
                                          label: label,
                                          protocol: protocolMark(
                                            _preview[i].scheme,
                                          ),
                                          dialable: dialable,
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
            text,
            style: TextStyle(
              fontSize: 12.5,
              letterSpacing: 0.2,
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

class _WindowsAddScreen extends StatelessWidget {
  const _WindowsAddScreen({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onPaste,
    required this.onClear,
    required this.onBack,
    required this.onSave,
    required this.loading,
    required this.errorText,
    required this.unsupportedText,
    required this.previewTitle,
    required this.preview,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onPaste;
  final VoidCallback onClear;
  final VoidCallback onBack;
  final VoidCallback? onSave;
  final bool loading;
  final String? errorText;
  final String? unsupportedText;
  final String? previewTitle;
  final List<ParsedShareLink> preview;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;

    return NightBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          title: Text(l.freeAddTitle),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final wide = box.maxWidth >= 720;
                          final link = _linkPanel(
                            l,
                            theme,
                            mute,
                            fill: wide,
                          );
                          final found = _foundPanel(
                            l,
                            theme,
                            mute,
                            fill: wide,
                          );
                          if (!wide) {
                            return ListView(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              children: [
                                link,
                                const SizedBox(height: 14),
                                found,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 340, child: link),
                              const SizedBox(width: 18),
                              Expanded(child: found),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    _footer(l, theme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _linkPanel(
    AppL10n l,
    ThemeData theme,
    Color mute, {
    required bool fill,
  }) {
    return AppSurface(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _ImportSectionHeader(
            icon: AppIcons.link,
            title: l.freeStepLink,
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(AppBrand.radiusCard),
              border: Border.all(
                color: focusNode.hasFocus
                    ? AppBrand.mascotGold.withValues(alpha: 0.75)
                    : theme.colorScheme.outline.withValues(alpha: 0.6),
                width: focusNode.hasFocus ? 1.6 : 1,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 3,
              onChanged: onChanged,
              cursorColor: AppBrand.mascotGold,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'JetBrainsMono',
                fontFamilyFallback: const ['Onest'],
                fontSize: 14,
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText: l.freeAddHint,
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: mute.withValues(alpha: 0.6),
                  fontFamily: 'JetBrainsMono',
                  fontFamilyFallback: const ['Onest'],
                  fontSize: 13.5,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l.freePaste,
                      onPressed: onPaste,
                      icon: const AppIcon(AppIcons.clipboard, size: 18),
                    ),
                    if (controller.text.isNotEmpty)
                      IconButton(
                        onPressed: onClear,
                        icon: const AppIcon(AppIcons.x, size: 18),
                      ),
                  ],
                ),
                suffixIconConstraints: const BoxConstraints(
                  minHeight: 48,
                  minWidth: 48,
                ),
              ),
            ),
          ),
          if (loading) ...[
            const SizedBox(height: 12),
            const SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                color: AppBrand.mascotGold,
                backgroundColor: Colors.transparent,
              ),
            ),
          ],
          if (errorText != null) ...[
            const SizedBox(height: 12),
            _ErrorLine(errorText!),
          ],
          if (unsupportedText != null) ...[
            const SizedBox(height: 12),
            Text(
              unsupportedText!,
              style: TextStyle(
                color: mute,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          if (fill) ...[
            const Spacer(),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppIcon(AppIcons.shieldCheck, size: 16, color: mute),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.vpnDisclosureBullet2,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: mute,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _foundPanel(
    AppL10n l,
    ThemeData theme,
    Color mute, {
    required bool fill,
  }) {
    final content = loading
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
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
        : preview.isEmpty
            ? _ImportEmpty(l.freeFoundEmpty)
            : _previewList(l);

    return AppSurface(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _ImportSectionHeader(
            icon: AppIcons.servers,
            title: l.freeStepFound,
            trailing: preview.isEmpty
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppBrand.mascotGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${preview.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppBrand.mascotGoldLit,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          if (previewTitle != null && previewTitle!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              previewTitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (fill)
            Expanded(
              child: preview.isEmpty || loading
                  ? Center(child: content)
                  : SingleChildScrollView(child: content),
            )
          else
            content,
        ],
      ),
    );
  }

  Widget _previewList(AppL10n l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < preview.length; i++) ...[
          if (i > 0) const NodeRule(),
          Builder(
            builder: (context) {
              final label = labelForShareLink(preview[i]);
              final dialable = canDialLink(preview[i]);
              return NodeLine(
                label: label,
                protocol: protocolMark(preview[i].scheme),
                dialable: dialable,
                endpoint: dialable
                    ? (label.subtitle.isEmpty
                        ? preview[i].endpoint
                        : label.subtitle)
                    : l.freeSchemeParked,
                selected: false,
                onTap: () {},
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _footer(AppL10n l, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const AppIcon(AppIcons.back, size: 16),
            label: Text(l.navBack),
          ),
          const Spacer(),
          AppActionButton(
            onPressed: onSave,
            icon: AppIcons.check,
            label: l.freeSaveConnect,
            color: AppBrand.mascotGold,
            height: 46,
            expand: false,
          ),
        ],
      ),
    );
  }
}

class _ImportSectionHeader extends StatelessWidget {
  const _ImportSectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        AppIcon(icon, size: 18, color: AppBrand.mascotGold),
        const SizedBox(width: 9),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          trailing!,
        ],
      ],
    );
  }
}

class _ImportEmpty extends StatelessWidget {
  const _ImportEmpty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: AppIcon(AppIcons.search, size: 20, color: mute),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: mute,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
