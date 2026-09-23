import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ios_store_gates.dart';
import '../../home/application/vpn_provider.dart';
import '../data/hy2_import_store.dart';
import '../data/hy2_link_parser.dart';

/// Paste a key or subscription URL, then connect. Android and iOS (ADR 026).
class Hy2ImportScreen extends ConsumerStatefulWidget {
  const Hy2ImportScreen({super.key});

  @override
  ConsumerState<Hy2ImportScreen> createState() => _Hy2ImportScreenState();
}

class _Hy2ImportScreenState extends ConsumerState<Hy2ImportScreen> {
  final _controller = TextEditingController();
  List<ParsedHy2Link> _links = const [];
  int _selected = 0;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final links = await Hy2ImportStore.instance.load();
    final selected = await Hy2ImportStore.instance.selectedIndex();
    if (!mounted) return;
    setState(() {
      _links = links;
      _selected = links.isEmpty ? 0 : selected.clamp(0, links.length - 1);
    });
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    _controller.text = text;
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final links = await Hy2ImportStore.instance.saveInput(_controller.text);
      if (!mounted) return;
      setState(() {
        _links = links;
        _selected = 0;
        _busy = false;
      });
    } on FormatException catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = err.message;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = err.toString();
      });
    }
  }

  Future<void> _connect() async {
    await Hy2ImportStore.instance.select(_selected);
    if (!mounted) return;
    await ref.read(vpnProvider.notifier).connect(forceRestart: true);
  }

  @override
  Widget build(BuildContext context) {
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    if (!hideInAppPlategaCheckout) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return Scaffold(
      appBar: AppBar(title: Text(ru ? 'Ссылка' : 'Link')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            ru
                ? 'Вставьте hysteria2:// или ссылку подписки. Приложение не продаёт доступ.'
                : 'Paste a hysteria2:// link or a subscription URL. This app does not sell access.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: ru ? 'Ссылка' : 'Link',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: _busy ? null : _pasteClipboard,
                child: Text(ru ? 'Из буфера' : 'Clipboard'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(ru ? 'Сохранить' : 'Save'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          for (var i = 0; i < _links.length; i++)
            ListTile(
              selected: i == _selected,
              title: Text(_links[i].name),
              subtitle: Text(_links[i].profile.server),
              onTap: () => setState(() => _selected = i),
            ),
          if (_links.isNotEmpty) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _connect,
              child: Text(ru ? 'Подключить' : 'Connect'),
            ),
          ],
        ],
      ),
    );
  }
}
