import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/notebook_paper.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../data/hy2_import_store.dart';
import '../data/share_link_parser.dart';
import '../data/subscription_link_inbox.dart';
import '../data/subscription_label.dart';
import 'free_client_chrome.dart';
import 'pool_server_mark.dart';

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
          _error = result.links.isEmpty ? 'empty' : null;
        });
      }).catchError((Object _) {
        if (!mounted || gen != _previewGen) return;
        setState(() {
          _loadingPreview = false;
          _preview = const [];
          _previewTitle = null;
          _error = 'load';
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
      setState(() {
        _preview = links;
        _error = text.isEmpty || links.isNotEmpty ? null : 'empty';
      });
    } on FormatException {
      setState(() {
        _preview = const [];
        _error = 'bad';
      });
    }
  }

  bool get _canSave =>
      !_busy &&
      !_loadingPreview &&
      _error == null &&
      (_subscriptionUrl || _preview.isNotEmpty);

  Future<void> _save({required bool connect}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final links = await Hy2ImportStore.instance.saveInput(_controller.text);
      if (!mounted) return;
      showTeremokSnackBar(context, AppL10n.of(context).freeServerAdded);
      if (connect && links.isNotEmpty) {
        if (!mounted) return;
        await ref.read(vpnProvider.notifier).connect(forceRestart: true);
        if (!mounted) return;
        context.go('/home');
        return;
      }
      if (!mounted) return;
      context.go('/locations');
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'bad';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'bad';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    if (!hideInAppPlategaCheckout) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final theme = Theme.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return NotebookPaper(
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    Text(
                      l.freeAddHint,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _controller,
                      focusNode: _fieldFocus,
                      minLines: keyboard ? 2 : 4,
                      maxLines: keyboard ? 3 : 6,
                      onChanged: _previewInput,
                      decoration: InputDecoration(
                        hintText: l.freeAddHint,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _controller.clear();
                                  _previewInput('');
                                },
                                icon: const AppIcon(AppIcons.x, size: 18),
                              ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppBrand.radiusCard),
                          borderSide:
                              BorderSide(color: theme.colorScheme.outline),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FreeClientActionBar(
                      onPaste: _pasteClipboard,
                      onScan: () => context.push('/scan'),
                    ),
                    if (_loadingPreview) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error == 'load'
                            ? l.freeSubscriptionLoadFail
                            : l.freeLinkInvalid,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      l.freePreview,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_previewTitle != null && _previewTitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _previewTitle!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    if (_loadingPreview)
                      const SizedBox.shrink()
                    else if (_error != null)
                      const SizedBox.shrink()
                    else if (_preview.isEmpty)
                      const FreeClientEmptyState(compact: true)
                    else
                      for (var i = 0; i < _preview.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final label = labelForShareLink(_preview[i]);
                            return ListTile(
                              leading: PoolServerMark(label: label),
                              title: Text(label.title),
                              subtitle: Text(
                                label.subtitle.isEmpty
                                    ? _preview[i].endpoint
                                    : label.subtitle,
                              ),
                            );
                          },
                        ),
                      ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _canSave ? () => _save(connect: true) : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppBrand.radiusPill),
                  ),
                ),
                child: Text(l.freeSaveConnect),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _canSave ? () => _save(connect: false) : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: theme.colorScheme.onSurface,
                  side: BorderSide(
                    color: theme.colorScheme.outline,
                    width: 1.4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppBrand.radiusPill),
                  ),
                ),
                child: Text(l.freeSaveOnly),
              ),
            ],
          ),
        ),
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
        color: dark ? AppBrand.surfaceVariantDark : AppBrand.surfaceElevatedLight,
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
