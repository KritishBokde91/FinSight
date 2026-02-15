package com.genzloop.finsight

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * Native BroadcastReceiver that fires whenever a new SMS is received,
 * even when the Flutter app is completely killed.
 *
 * It stores the SMS in SharedPreferences so the background Dart isolate
 * can pick it up on the next periodic check. It also attempts a direct
 * POST to the backend for immediate delivery.
 */
class SmsReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsReceiver"
        private const val PREFS_NAME = "finsight_sms_prefs"
        private const val PENDING_SMS_KEY = "pending_sms"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (context == null) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        val smsList = mutableListOf<Map<String, Any>>()
        for (msg in messages) {
            val smsMap = mapOf(
                "sender" to (msg.displayOriginatingAddress ?: "Unknown"),
                "body" to (msg.displayMessageBody ?: ""),
                "timestamp" to msg.timestampMillis,
                "date_sent" to msg.timestampMillis,
                "type" to 1 // 1 = inbox
            )
            smsList.add(smsMap)
            Log.d(TAG, "New SMS from: ${smsMap["sender"]}")
        }

        // Store in SharedPreferences for the Dart isolate to pick up
        storePendingSms(context, smsList)

        // Also update the last sync timestamp
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit().putLong("flutter.last_sync_timestamp", System.currentTimeMillis()).apply()

        Log.d(TAG, "Stored ${smsList.size} SMS for processing")
    }

    private fun storePendingSms(context: Context, newSms: List<Map<String, Any>>) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val existingJson = prefs.getString(PENDING_SMS_KEY, "[]") ?: "[]"

        try {
            val existingArray = JSONArray(existingJson)

            for (sms in newSms) {
                val obj = JSONObject()
                obj.put("sender", sms["sender"])
                obj.put("body", sms["body"])
                obj.put("timestamp", sms["timestamp"])
                obj.put("date_sent", sms["date_sent"])
                obj.put("type", sms["type"])
                existingArray.put(obj)
            }

            prefs.edit().putString(PENDING_SMS_KEY, existingArray.toString()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error storing pending SMS: ${e.message}")
        }
    }
}
