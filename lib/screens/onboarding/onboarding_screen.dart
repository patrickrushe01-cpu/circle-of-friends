import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../models/contact.dart';
import '../../state/onboarding_state.dart';
import '../radar/radar_screen.dart';
import 'contact_picker_step.dart';
import 'permission_step.dart';

/// Runs once, per DESIGN.md §3/§8: contact selection, then permissions,
/// then hand off to the radar.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  List<fc.Contact> _selected = [];

  Future<void> _saveContactsAndAdvance(List<fc.Contact> contacts) async {
    setState(() {
      _selected = contacts;
      _step = 1;
    });
  }

  Future<void> _finishOnboarding() async {
    final database = ref.read(appDatabaseProvider);
    for (final contact in _selected) {
      await database.addContact(
        Contact()
          ..deviceContactId = contact.id
          ..name = contact.displayName
          ..avatarRef = null
          ..dateAdded = DateTime.now(),
      );
    }
    await markOnboardingComplete();
    ref.invalidate(onboardingCompleteProvider);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RadarScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your circle')),
      body: switch (_step) {
        0 => ContactPickerStep(onSelectionComplete: _saveContactsAndAdvance),
        _ => PermissionStep(onComplete: _finishOnboarding),
      },
    );
  }
}
