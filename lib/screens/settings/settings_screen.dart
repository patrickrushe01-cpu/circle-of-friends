import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../database/app_database.dart';
import '../../models/contact.dart';
import '../../platform/email/gmail_email_provider.dart';
import '../../services/permission_service.dart';

/// Manage the tracked ten and review permissions, per DESIGN.md §8.
/// Swapping a contact is deliberately a distinct, confirm-first action
/// (see DESIGN.md §7) rather than a casual inline edit, since it
/// soft-deletes history for the outgoing contact.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final database = ref.watch(appDatabaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Your circle'),
          StreamBuilder<List<Contact>>(
            stream: database.watchTrackedContacts(),
            builder: (context, snapshot) {
              final contacts = snapshot.data ?? const <Contact>[];
              return Column(
                children: contacts
                    .map((c) => ListTile(
                          title: Text(c.name),
                          trailing: TextButton(
                            child: const Text('Swap'),
                            onPressed: () => _confirmSwap(context, ref, c),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
          const Divider(),
          const _SectionHeader('Permissions'),
          const _PermissionsList(),
          const Divider(),
          const _SectionHeader('Email'),
          const _EmailConnectionTile(),
          const Divider(),
          const _SectionHeader('Data'),
          ListTile(
            title: const Text('Export my data'),
            subtitle: const Text('Everything stays on-device — export is '
                'the only way to back it up.'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Export not yet implemented')),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSwap(
    BuildContext context,
    WidgetRef ref,
    Contact outgoing,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Swap out ${outgoing.name}?'),
        content: const Text(
          'Their history is kept, but they\'ll stop appearing on the '
          'radar. You\'ll pick a replacement next.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final granted = await fc.FlutterContacts.requestPermission();
    if (!granted || !context.mounted) return;

    final replacement = await showModalBottomSheet<fc.Contact>(
      context: context,
      builder: (_) => const _ReplacementPicker(),
    );
    if (replacement == null) return;

    final database = ref.read(appDatabaseProvider);
    await database.swapContact(
      oldContactId: outgoing.id,
      newContact: Contact()
        ..deviceContactId = replacement.id
        ..name = replacement.displayName
        ..phoneNumbers = replacement.phones.map((p) => p.number).toList()
        ..emailAddresses = replacement.emails.map((e) => e.address).toList()
        ..dateAdded = DateTime.now(),
    );
  }
}

class _ReplacementPicker extends StatelessWidget {
  const _ReplacementPicker();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<fc.Contact>>(
      future: fc.FlutterContacts.getContacts(withProperties: true),
      builder: (context, snapshot) {
        final contacts = snapshot.data ?? const <fc.Contact>[];
        return ListView.builder(
          itemCount: contacts.length,
          itemBuilder: (context, index) {
            final contact = contacts[index];
            return ListTile(
              title: Text(contact.displayName),
              onTap: () => Navigator.pop(context, contact),
            );
          },
        );
      },
    );
  }
}

class _PermissionsList extends StatefulWidget {
  const _PermissionsList();

  @override
  State<_PermissionsList> createState() => _PermissionsListState();
}

class _PermissionsListState extends State<_PermissionsList> {
  final _service = const PermissionService();
  Map<TrackedPermission, PermissionStatus> _statuses = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final statuses = <TrackedPermission, PermissionStatus>{};
    for (final permission in _service.requestOrder) {
      statuses[permission] = await _service.statusOf(permission);
    }
    if (mounted) setState(() => _statuses = statuses);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _statuses.entries.map((entry) {
        final granted = entry.value.isGranted;
        return ListTile(
          title: Text(_label(entry.key)),
          trailing: granted
              ? const Icon(Icons.check_circle, color: Colors.green)
              : TextButton(
                  onPressed: () async {
                    await _service.request(entry.key);
                    _refresh();
                  },
                  child: const Text('Grant'),
                ),
        );
      }).toList(),
    );
  }

  String _label(TrackedPermission permission) {
    switch (permission) {
      case TrackedPermission.contacts:
        return 'Contacts';
      case TrackedPermission.calendar:
        return 'Calendar';
      case TrackedPermission.callLog:
        return 'Call log (Android)';
      case TrackedPermission.sms:
        return 'SMS (Android)';
    }
  }
}

/// Lets the user connect Gmail so email frequency counts toward scoring,
/// per DESIGN.md §2/§6. Optional — the app works without it, just with
/// one fewer signal (see [EmailCollector]'s silent no-op when
/// disconnected).
class _EmailConnectionTile extends StatefulWidget {
  const _EmailConnectionTile();

  @override
  State<_EmailConnectionTile> createState() => _EmailConnectionTileState();
}

class _EmailConnectionTileState extends State<_EmailConnectionTile> {
  final _provider = GmailEmailProvider();
  bool? _connected;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final connected = await _provider.isConnected();
    if (mounted) setState(() => _connected = connected);
  }

  @override
  Widget build(BuildContext context) {
    if (_connected == null) {
      return const ListTile(title: Text('Checking email connection…'));
    }
    return ListTile(
      title: const Text('Gmail'),
      subtitle: Text(_connected!
          ? 'Connected — message frequency counts toward staying in touch.'
          : 'Not connected. Only frequency and timestamps are read, never '
              'subjects or content.'),
      trailing: _connected!
          ? TextButton(
              onPressed: () async {
                await _provider.disconnect();
                _refresh();
              },
              child: const Text('Disconnect'),
            )
          : FilledButton(
              onPressed: () async {
                await _provider.connect();
                _refresh();
              },
              child: const Text('Connect'),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
