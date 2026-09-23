import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../data/hy2_import_store.dart';
import '../data/share_link_parser.dart';
import 'free_client_chrome.dart';

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
  String? _error;
  bool _busy = false;
  var _clipboardApplied = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    try {
      final links = parseShareSubscription(raw.trim());
      setState(() {
        _preview = links;
        _error = links.isEmpty ? 'empty' : null;
      });
    } on FormatException {
      setState(() {
        _preview = const [];
        _error = 'bad';
      });
    }
  }

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
        await Hy2ImportStore.instance.select(0);
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
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: Text(l.freeAddTitle)),
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
                      onAdd: () => _fieldFocus.requestFocus(),
                      onPaste: _pasteClipboard,
                      onScan: () => context.push('/scan'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        l.freeLinkInvalid,
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
                    if (_preview.isEmpty)
                      const FreeClientEmptyState(compact: true)
                    else
                      for (var i = 0; i < _preview.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        ImportedProfileCard(
                          name: _preview[i].name,
                          scheme: _preview[i].scheme,
                          endpoint: _preview[i].endpoint,
                          selected: i == 0,
                        ),
                      ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy || _preview.isEmpty
                    ? null
                    : () => _save(connect: true),
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
                onPressed: _busy || _preview.isEmpty
                    ? null
                    : () => _save(connect: false),
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
    );
  }
}
