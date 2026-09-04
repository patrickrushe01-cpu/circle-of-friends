import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../models/interaction.dart';
import 'radar_point.dart';

/// The tap-an-avatar bottom sheet from DESIGN.md §8: recent interaction
/// timeline plus a last-in-touch summary.
class ContactDetailSheet extends ConsumerWidget {
  const ContactDetailSheet({super.key, required this.point});

  final RadarPoint point;

  static void show(BuildContext context, RadarPoint point) {
    showModalBottomSheet(
      context: context,
      builder: (_) => ContactDetailSheet(point: point),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final database = ref.watch(appDatabaseProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      builder: (context, scrollController) {
        return FutureBuilder(
          future: database.recentInteractionsForContact(point.contactId),
          builder: (context, snapshot) {
            final interactions = snapshot.data ?? const <Interaction>[];
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                Text(point.name, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(point.lastInteractionLabel,
                    style: Theme.of(context).textTheme.bodyMedium),
                const Divider(height: 32),
                if (interactions.isEmpty)
                  const Text('No interactions logged yet.')
                else
                  ...interactions.map(
                    (interaction) => ListTile(
                      leading: Icon(_iconFor(interaction.source)),
                      title: Text(_labelFor(interaction)),
                      subtitle: Text(_formatDate(interaction.timestamp)),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  IconData _iconFor(InteractionSource source) {
    switch (source) {
      case InteractionSource.call:
        return Icons.call;
      case InteractionSource.text:
        return Icons.sms;
      case InteractionSource.calendar:
        return Icons.event;
      case InteractionSource.email:
        return Icons.email;
      case InteractionSource.manual:
        return Icons.edit_note;
    }
  }

  String _labelFor(Interaction interaction) {
    switch (interaction.source) {
      case InteractionSource.call:
        return 'Call';
      case InteractionSource.text:
        return 'Text';
      case InteractionSource.calendar:
        return 'Calendar meeting';
      case InteractionSource.email:
        return 'Email';
      case InteractionSource.manual:
        return switch (interaction.manualType) {
          ManualInteractionType.call => 'Logged: call',
          ManualInteractionType.text => 'Logged: text',
          ManualInteractionType.inPerson => 'Logged: in person',
          ManualInteractionType.other => 'Logged: other',
          null => 'Logged check-in',
        };
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
