import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/application/vpn_provider.dart';
import '../data/vpn_node.dart';

/// Bottom sheet to pick a Marzban multi-node egress region.
Future<void> showRegionPicker(BuildContext context, WidgetRef ref) async {
  final nodesRepo = ref.read(vpnNodesRepositoryProvider);
  List<VpnNode> nodes;
  String? selectedId;
  try {
    nodes = await nodesRepo.listNodes();
    selectedId = await nodesRepo.getSelectedNodeId();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load nodes: $e')),
      );
    }
    return;
  }

  if (!context.mounted) return;
  if (nodes.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No VPN nodes available')),
    );
    return;
  }

  selectedId ??= nodes.where((n) => n.isDefault).map((n) => n.id).firstOrNull ??
      nodes.first.id;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Region'),
              subtitle: Text('Select VPN egress node'),
            ),
            for (final node in nodes)
              RadioListTile<String>(
                value: node.id,
                groupValue: selectedId,
                title: Text(node.label.isNotEmpty ? node.label : node.host),
                subtitle: Text('${node.host}:${node.port} · ${node.status}'),
                onChanged: node.isConnected || node.isDefault
                    ? (value) async {
                        if (value == null) return;
                        Navigator.of(ctx).pop();
                        try {
                          await ref.read(vpnProvider.notifier).selectNode(value);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Region: ${node.label.isNotEmpty ? node.label : node.host}',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Region change failed: $e')),
                            );
                          }
                        }
                      }
                    : null,
              ),
          ],
        ),
      );
    },
  );
}
