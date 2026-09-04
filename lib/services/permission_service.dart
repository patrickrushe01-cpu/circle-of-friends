import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Baseline permissions requested on every platform, plus the
/// Android-only extras. Kept as an explicit enum (rather than raw
/// `Permission` values scattered through onboarding) so the reason-per-
/// permission copy in the onboarding screen has one source of truth to
/// key off — see DESIGN.md §8.
enum TrackedPermission { contacts, calendar, callLog, sms }

class PermissionService {
  const PermissionService();

  /// The permissions this build should ask for, in the order they should
  /// be requested. Call log/SMS are Android-only per the hard iOS platform
  /// restriction described in DESIGN.md §2.
  List<TrackedPermission> get requestOrder => [
        TrackedPermission.contacts,
        TrackedPermission.calendar,
        if (Platform.isAndroid) TrackedPermission.callLog,
        if (Platform.isAndroid) TrackedPermission.sms,
      ];

  Future<PermissionStatus> statusOf(TrackedPermission permission) {
    return _resolve(permission).status;
  }

  Future<PermissionStatus> request(TrackedPermission permission) {
    return _resolve(permission).request();
  }

  Permission _resolve(TrackedPermission permission) {
    switch (permission) {
      case TrackedPermission.contacts:
        return Permission.contacts;
      case TrackedPermission.calendar:
        return Permission.calendarFullAccess;
      case TrackedPermission.callLog:
        return Permission.phone;
      case TrackedPermission.sms:
        return Permission.sms;
    }
  }

  String reasonFor(TrackedPermission permission) {
    switch (permission) {
      case TrackedPermission.contacts:
        return 'To choose your ten and show their names and photos.';
      case TrackedPermission.calendar:
        return 'Meetings with your circle count toward staying in touch.';
      case TrackedPermission.callLog:
        return 'Calls with your circle count toward staying in touch.';
      case TrackedPermission.sms:
        return 'Texts with your circle count toward staying in touch.';
    }
  }
}
