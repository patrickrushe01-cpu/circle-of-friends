import 'package:isar/isar.dart';

part 'interaction.g.dart';

enum InteractionSource { call, text, calendar, email, manual }

/// For manual check-ins only — the brief's four tap-to-log types.
/// Null for automatically-collected sources (call/text/calendar/email),
/// where the source itself already implies the interaction shape.
enum ManualInteractionType { call, text, inPerson, other }

/// One row per real-world interaction event, from any source.
@collection
class Interaction {
  Id id = Isar.autoIncrement;

  @Index()
  late int contactId;

  @Index()
  late DateTime timestamp;

  @enumerated
  late InteractionSource source;

  // Isar's default `@enumerated` (EnumType.ordinal) stores a single
  // non-nullable byte, which doesn't support null — this field needs
  // ordinal32 (a nullable int) since only manual check-ins set it.
  @Enumerated(EnumType.ordinal32)
  ManualInteractionType? manualType;

  /// Calls and calendar meetings only; null otherwise.
  int? durationSeconds;
}
