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
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    final granted =
        status == PermissionStatus.granted || status == PermissionStatus.limited;
    if (!granted) {
      setState(() => _loading = false);
      return;
    }
    final contacts = await FlutterContacts.getAll(
      properties: {
        ContactProperty.phone,
        ContactProperty.email,
        ContactProperty.photoThumbnail,
      },
    );
    // id/displayName are nullable in this API but every real address-book
    // entry has both; drop anything that doesn't rather than thread
    // nullability through the whole selection flow.
    final usable = contacts.where((c) => c.id != null).toList()
      ..sort((a, b) => (a.displayName ?? '').compareTo(b.displayName ?? ''));
    setState(() {
      _allContacts = usable;
      _loading = false;
    });
  }

  void _toggle(Contact contact) {
    final id = contact.id!;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else if (_selectedIds.length < trackedCount) {
        _selectedIds.add(id);
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
              final name = contact.displayName ?? '';
              final selected = _selectedIds.contains(contact.id);
              final disabled = !selected && atCapacity;
              final thumbnail = contact.photo?.thumbnail;
              return Opacity(
                opacity: disabled ? 0.4 : 1.0,
                child: CheckboxListTile(
                  value: selected,
                  onChanged: disabled ? null : (_) => _toggle(contact),
                  title: Text(name),
                  secondary: CircleAvatar(
                    backgroundImage:
                        thumbnail != null ? MemoryImage(thumbnail) : null,
                    child: thumbnail == null
                        ? Text(name.isNotEmpty ? name[0] : '?')
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
