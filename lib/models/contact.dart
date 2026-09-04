import 'package:isar/isar.dart';

part 'contact.g.dart';

/// One of the ten tracked contacts. Soft-deleted (active = false) rather
/// than removed outright, so historical interactions/scores stay meaningful
/// after a swap — see DESIGN.md §7.
@collection
class Contact {
  Id id = Isar.autoIncrement;

  /// Stable identifier into the OS address book, used to re-resolve name/
  /// avatar if they change, and to prevent adding the same person twice.
  @Index(unique: true, replace: false)
  late String deviceContactId;

  late String name;

  /// Cached avatar reference (local file path or bytes handle). Nullable —
  /// not every contact has a photo.
  String? avatarRef;

  late DateTime dateAdded;

  /// False once swapped out via Settings. Kept for historical trend data.
  bool active = true;
}
