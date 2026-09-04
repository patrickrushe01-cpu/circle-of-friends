import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../models/contact.dart';
import '../../models/interaction.dart';
import '../../services/scoring_service.dart';

/// The structured, no-typing check-in flow from DESIGN.md §8: tap names,
/// tap an interaction type. Triggered by a notification or the radar's
/// floating action button. Multiple contacts can be logged in one pass.
class CheckinModal extends ConsumerStatefulWidget {
  const CheckinModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const CheckinModal(),
    );
  }

  @override
  ConsumerState<CheckinModal> createState() => _CheckinModalState();
}

class _CheckinModalState extends ConsumerState<CheckinModal> {
  final Set<int> _selectedContactIds = {};
  ManualInteractionType? _type;
  bool _saving = false;

  Future<void> _save() async {
    if (_selectedContactIds.isEmpty || _type == null) return;
    setState(() => _saving = true);

    final database = ref.read(appDatabaseProvider);
    final now = DateTime.now();
    for (final contactId in _selectedContactIds) {
      await database.logInteraction(
        Interaction()
          ..contactId = contactId
          ..timestamp = now
          ..source = InteractionSource.manual
          ..manualType = _type,
      );
    }
    // Recompute immediately so the radar reflects the check-in right
    // away, rather than waiting for the next hourly tick.
    await ScoringService(database).recomputeTick();

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(appDatabaseProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: FutureBuilder<List<Contact>>(
        future: database.trackedContacts(),
        builder: (context, snapshot) {
          final contacts = snapshot.data ?? const <Contact>[];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Catch up with anyone today?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: contacts.map((contact) {
                  final selected = _selectedContactIds.contains(contact.id);
                  return FilterChip(
                    label: Text(contact.name),
                    selected: selected,
                    onSelected: (value) => setState(() {
                      value
                          ? _selectedContactIds.add(contact.id)
                          : _selectedContactIds.remove(contact.id);
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Text('How?', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: ManualInteractionType.values.map((type) {
                  return ChoiceChip(
                    label: Text(_labelFor(type)),
                    selected: _type == type,
                    onSelected: (_) => setState(() => _type = type),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed:
                    (_selectedContactIds.isNotEmpty && _type != null && !_saving)
                        ? _save
                        : null,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Log it'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _labelFor(ManualInteractionType type) {
    switch (type) {
      case ManualInteractionType.call:
        return 'Call';
      case ManualInteractionType.text:
        return 'Text';
      case ManualInteractionType.inPerson:
        return 'In person';
      case ManualInteractionType.other:
        return 'Other';
    }
  }
}
