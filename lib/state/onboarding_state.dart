import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingCompleteKey = 'onboarding_complete';

/// Whether the user has finished picking their ten and granting the
/// baseline permissions. Backed by SharedPreferences since it's a single
/// flag, not domain data — the tracked ten itself lives in the Isar
/// `contacts` table via [AppDatabase].
final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kOnboardingCompleteKey) ?? false;
});

Future<void> markOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kOnboardingCompleteKey, true);
}
