import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

/// Step 1 of onboarding: pick exactly ten contacts, per DESIGN.md §8.
/// Selection is capped — the tenth tap disables every unselected tile
/// until one is deselected, rather than silently truncating an eleventh
/// pick.
class ContactPickerStep extends StatefulWidget {
  const ContactPickerStep({super.key, required this.onSelectionComplete});

  final ValueChanged<List<Contact>> onSelectionComplete;

  @override
  State<ContactPickerStep> createState() => _ContactPickerStepState();
}

class _ContactPickerStepState extends State<ContactPickerStep> {
  static const trackedCount = 10;

  List<Contact> _allContacts = [];
  final Set<String> _selectedIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final granted = await FlutterContacts.requestPermission();
    if (!granted) {
      setState(() => _loading = false);
      return;
    }
    final contacts = await FlutterContacts.getContacts(
      withPhoto: true,
      withProperties: true,
    );
    contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
    setState(() {
      _allContacts = contacts;
      _loading = false;
    });
  }

  void _toggle(Contact contact) {
    setState(() {
      if (_selectedIds.contains(contact.id)) {
        _selectedIds.remove(contact.id);
      } else if (_selectedIds.length < trackedCount) {
        _selectedIds.add(contact.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final atCapacity = _selectedIds.length == trackedCount;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${_selectedIds.length} of $trackedCount selected',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _allContacts.length,
            itemBuilder: (context, index) {
              final contact = _allContacts[index];
              final selected = _selectedIds.contains(contact.id);
              final disabled = !selected && atCapacity;
              return Opacity(
                opacity: disabled ? 0.4 : 1.0,
                child: CheckboxListTile(
                  value: selected,
                  onChanged: disabled ? null : (_) => _toggle(contact),
                  title: Text(contact.displayName),
                  secondary: CircleAvatar(
                    backgroundImage: contact.photo != null
                        ? MemoryImage(contact.photo!)
                        : null,
                    child: contact.photo == null
                        ? Text(contact.displayName.isNotEmpty
                            ? contact.displayName[0]
                            : '?')
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: atCapacity
                ? () => widget.onSelectionComplete(
                      _allContacts
                          .where((c) => _selectedIds.contains(c.id))
                          .toList(),
                    )
                : null,
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }
}
