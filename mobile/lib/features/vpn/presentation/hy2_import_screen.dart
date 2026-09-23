import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(l.freeAddTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                minLines: 4,
                maxLines: 6,
                onChanged: _previewInput,
                decoration: InputDecoration(
                  hintText: l.freeAddHint,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppBrand.radiusCard),
                    borderSide: BorderSide(color: theme.colorScheme.outline),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FreeClientActionBar(
                onAdd: () => _controller.clear(),
                onPaste: _pasteClipboard,
                onScan: () => context.push('/scan'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  l.homeError,
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
              Expanded(
                child: _preview.isEmpty
                    ? const Center(child: FreeClientEmptyState(compact: true))
                    : ListView.separated(
                        itemCount: _preview.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final link = _preview[i];
                          return ImportedProfileCard(
                            name: link.name,
                            scheme: link.scheme,
                            endpoint: link.endpoint,
                            selected: i == 0,
                          );
                        },
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
                  side: BorderSide(color: theme.colorScheme.outline, width: 1.4),
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
