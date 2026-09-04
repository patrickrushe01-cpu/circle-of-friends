package com.circleoffriends.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Registers the `circle_of_friends/call_sms` MethodChannel that
 * `lib/platform/call_sms_channel.dart` talks to. Android-only — see
 * DESIGN.md §2 for why this has no iOS counterpart.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "circle_of_friends/call_sms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val reader = CallLogSmsReader(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "fetchEventsSince" -> {
                        val phoneNumbers = call.argument<List<String>>("phoneNumbers") ?: emptyList()
                        val sinceMillis = call.argument<Long>("sinceMillis") ?: 0L

                        try {
                            val events = reader.fetchEventsSince(phoneNumbers, sinceMillis)
                            result.success(events.map { event ->
                                mapOf(
                                    "phoneNumber" to event.phoneNumber,
                                    "timestamp" to event.timestampMillis,
                                    "isCall" to event.isCall,
                                    "durationSeconds" to event.durationSeconds,
                                )
                            })
                        } catch (e: SecurityException) {
                            result.error(
                                "PERMISSION_DENIED",
                                "Call log or SMS permission not granted",
                                e.message,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
