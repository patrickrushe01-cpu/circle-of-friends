import 'dart:io';

import 'package:flutter/services.dart';

/// A single call/SMS event read from the device content providers.
/// Mirrors the shape the Kotlin side serializes — see
/// `android/app/src/main/kotlin/.../CallLogSmsReader.kt`.
class RawDeviceEvent {
  RawDeviceEvent({
    required this.phoneNumber,
    required this.timestampMillis,
    required this.isCall,
    this.durationSeconds,
  });

  factory RawDeviceEvent.fromMap(Map<dynamic, dynamic> map) {
    return RawDeviceEvent(
      phoneNumber: map['phoneNumber'] as String,
      timestampMillis: map['timestamp'] as int,
      isCall: map['isCall'] as bool,
      durationSeconds: map['durationSeconds'] as int?,
    );
  }

  final String phoneNumber;
  final int timestampMillis;
  final bool isCall;
  final int? durationSeconds;

  DateTime get timestamp =>
      DateTime.fromMillisecondsSinceEpoch(timestampMillis);
}

/// Dart-side client for the native Android module. Android only, per the
/// hard iOS platform restriction in DESIGN.md §2 — callers must guard with
/// `Platform.isAndroid` before use, this class does not do it implicitly
/// so that an accidental iOS call fails loudly in development rather than
/// silently returning empty results.
class CallSmsChannel {
  const CallSmsChannel();

  static const _channel = MethodChannel('circle_of_friends/call_sms');

  /// Reads call log + SMS events for the given phone numbers since
  /// [since]. Numbers should be normalized (E.164 or digits-only) before
  /// calling — the native side does an exact match against the content
  /// provider's stored number format after its own normalization pass.
  Future<List<RawDeviceEvent>> fetchEventsSince({
    required List<String> phoneNumbers,
    required DateTime since,
  }) async {
    assert(Platform.isAndroid, 'CallSmsChannel is Android-only');
    final result = await _channel.invokeMethod<List<dynamic>>(
      'fetchEventsSince',
      {
        'phoneNumbers': phoneNumbers,
        'sinceMillis': since.millisecondsSinceEpoch,
      },
    );
    return (result ?? [])
        .cast<Map<dynamic, dynamic>>()
        .map(RawDeviceEvent.fromMap)
        .toList();
  }
}
