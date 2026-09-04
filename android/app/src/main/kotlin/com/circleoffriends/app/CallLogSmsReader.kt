package com.circleoffriends.app

import android.content.Context
import android.provider.CallLog
import android.provider.Telephony

/**
 * Reads call and SMS frequency directly from the device content
 * providers. No network calls, no server — this stays entirely on-device,
 * per DESIGN.md's privacy posture (§10).
 *
 * Only number, timestamp, and (for calls) duration are ever read — never
 * message body content.
 */
class CallLogSmsReader(private val context: Context) {

    data class DeviceEvent(
        val phoneNumber: String,
        val timestampMillis: Long,
        val isCall: Boolean,
        val durationSeconds: Int?,
    )

    /**
     * Returns call + SMS events for any of [phoneNumbers] since [sinceMillis].
     * Numbers are matched using [PhoneNumberUtils.compare]-style loose
     * matching so formatting differences (spaces, country code prefix)
     * between the address book and the log don't cause silent misses.
     */
    fun fetchEventsSince(phoneNumbers: List<String>, sinceMillis: Long): List<DeviceEvent> {
        val events = mutableListOf<DeviceEvent>()
        events.addAll(readCallLog(phoneNumbers, sinceMillis))
        events.addAll(readSms(phoneNumbers, sinceMillis))
        return events
    }

    private fun readCallLog(phoneNumbers: List<String>, sinceMillis: Long): List<DeviceEvent> {
        val events = mutableListOf<DeviceEvent>()
        val projection = arrayOf(
            CallLog.Calls.NUMBER,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION,
        )
        val selection = "${CallLog.Calls.DATE} >= ?"
        val selectionArgs = arrayOf(sinceMillis.toString())

        context.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            "${CallLog.Calls.DATE} DESC",
        )?.use { cursor ->
            val numberIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
            val dateIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.DATE)
            val durationIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.DURATION)

            while (cursor.moveToNext()) {
                val number = cursor.getString(numberIdx) ?: continue
                if (!matchesAny(number, phoneNumbers)) continue
                events.add(
                    DeviceEvent(
                        phoneNumber = number,
                        timestampMillis = cursor.getLong(dateIdx),
                        isCall = true,
                        durationSeconds = cursor.getInt(durationIdx),
                    )
                )
            }
        }
        return events
    }

    private fun readSms(phoneNumbers: List<String>, sinceMillis: Long): List<DeviceEvent> {
        val events = mutableListOf<DeviceEvent>()
        val projection = arrayOf(
            Telephony.Sms.ADDRESS,
            Telephony.Sms.DATE,
        )
        // Covers both sent and received — frequency only, per the brief;
        // direction is not currently modeled.
        val selection = "${Telephony.Sms.DATE} >= ?"
        val selectionArgs = arrayOf(sinceMillis.toString())

        context.contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            "${Telephony.Sms.DATE} DESC",
        )?.use { cursor ->
            val addressIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val dateIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)

            while (cursor.moveToNext()) {
                val address = cursor.getString(addressIdx) ?: continue
                if (!matchesAny(address, phoneNumbers)) continue
                events.add(
                    DeviceEvent(
                        phoneNumber = address,
                        timestampMillis = cursor.getLong(dateIdx),
                        isCall = false,
                        durationSeconds = null,
                    )
                )
            }
        }
        return events
    }

    /** Loose match on trailing digits, tolerant of country-code/formatting differences. */
    private fun matchesAny(candidate: String, targets: List<String>): Boolean {
        val candidateDigits = candidate.filter { it.isDigit() }.takeLast(9)
        if (candidateDigits.isEmpty()) return false
        return targets.any { target ->
            val targetDigits = target.filter { it.isDigit() }.takeLast(9)
            targetDigits.isNotEmpty() && targetDigits == candidateDigits
        }
    }
}
