import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/app_database.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/radar/radar_screen.dart';
import 'services/notification_service.dart';
import 'services/recompute_scheduler.dart';
import 'state/onboarding_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = await AppDatabase.open();
  await NotificationService.instance.init();
  await RecomputeScheduler.instance.initialize();

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
      ],
      child: const CircleOfFriendsApp(),
    ),
  );
}

class CircleOfFriendsApp extends ConsumerWidget {
  const CircleOfFriendsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingComplete = ref.watch(onboardingCompleteProvider);

    return MaterialApp(
      title: 'Circle of Friends',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF5B5FEF),
        brightness: Brightness.dark,
      ),
      home: onboardingComplete.when(
        data: (done) => done ? const RadarScreen() : const OnboardingScreen(),
        loading: () => const _SplashScreen(),
        error: (err, _) => _ErrorScreen(error: err),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('Something went wrong: $error')),
    );
  }
}
