import 'package:workmanager/workmanager.dart';

import '../database/app_database.dart';
import 'interaction_sync.dart';
import 'scoring_service.dart';

const hourlyRecomputeTask = 'hourly_recompute';

/// Schedules the hourly recompute described in DESIGN.md §6. Uses
/// `workmanager` on Android (backed by WorkManager/JobScheduler) — iOS
/// background execution is opportunistic by OS design, so the radar screen
/// also triggers a recompute on foreground/pull-to-refresh to compensate
/// for ticks the OS declined to run in the background.
class RecomputeScheduler {
  RecomputeScheduler._();
  static final instance = RecomputeScheduler._();

  Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      hourlyRecomputeTask,
      hourlyRecomputeTask,
      frequency: const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.not_required),
    );
  }
}

/// Top-level entry point required by workmanager — runs in a background
/// isolate, so it re-opens its own database handle rather than reusing
/// the foreground app's.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == hourlyRecomputeTask) {
      final database = await AppDatabase.open();
      await InteractionSync(database).syncAll();
      await ScoringService(database).recomputeTick();
    }
    return Future.value(true);
  });
}
