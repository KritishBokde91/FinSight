package com.genzloop.finsight

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.regex.Pattern

/**
 * NotificationListenerService that captures UPI payment notifications
 * from apps like Google Pay, PhonePe, Paytm, CRED, etc.
 *
 * Extracts amount, counterparty, and transaction type from notification text.
 * Stores captured data in SharedPreferences for the Dart isolate to pick up
 * and send to the backend API.
 */
class UpiNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "UpiNotificationListener"
        private const val PREFS_NAME = "finsight_notification_prefs"
        private const val PENDING_NOTIFICATIONS_KEY = "pending_notifications"

        // UPI app package names to listen for
        private val UPI_PACKAGES = setOf(
            "com.google.android.apps.nbu.paisa.user",  // Google Pay
            "com.phonepe.app",                           // PhonePe
            "net.one97.paytm",                           // Paytm
            "com.dreamplug.androidapp",                  // CRED
            "in.amazon.mShop.android.shopping",          // Amazon Pay
            "com.whatsapp",                              // WhatsApp Pay
            "com.mobikwik_new",                           // MobiKwik
            "com.freecharge.android",                     // Freecharge
            "com.myairtelapp",                            // Airtel Payments Bank
            "com.csam.icici.bank.imobile",                // iMobile Pay
            "com.sbi.SBIFreedomPlus",                     // YONO SBI
            "com.axis.mobile",                            // Axis Mobile
            "com.msf.kbank.mobile",                       // Kotak
        )

        // App display names
        private val APP_NAMES = mapOf(
            "com.google.android.apps.nbu.paisa.user" to "Google Pay",
            "com.phonepe.app" to "PhonePe",
            "net.one97.paytm" to "Paytm",
            "com.dreamplug.androidapp" to "CRED",
            "in.amazon.mShop.android.shopping" to "Amazon Pay",
            "com.whatsapp" to "WhatsApp Pay",
            "com.mobikwik_new" to "MobiKwik",
            "com.freecharge.android" to "Freecharge",
            "com.myairtelapp" to "Airtel Payments",
            "com.csam.icici.bank.imobile" to "iMobile Pay",
            "com.sbi.SBIFreedomPlus" to "YONO SBI",
            "com.axis.mobile" to "Axis Mobile",
            "com.msf.kbank.mobile" to "Kotak",
        )

        // Regex patterns to extract amount from notification text
        private val AMOUNT_PATTERNS = listOf(
            Pattern.compile("(?:₹|Rs\\.?|INR)\\s*([\\d,]+\\.?\\d*)", Pattern.CASE_INSENSITIVE),
            Pattern.compile("([\\d,]+\\.?\\d*)\\s*(?:₹|Rs\\.?|INR)", Pattern.CASE_INSENSITIVE),
            Pattern.compile("(?:amount|paid|received|sent|debited|credited)\\s*(?:of)?\\s*(?:₹|Rs\\.?|INR)?\\s*([\\d,]+\\.?\\d*)", Pattern.CASE_INSENSITIVE),
        )

        // Keywords to detect transaction type
        private val CREDIT_KEYWORDS = listOf("received", "credited", "credit", "cashback", "refund", "got")
        private val DEBIT_KEYWORDS = listOf("paid", "sent", "debited", "debit", "payment", "transferred", "spent")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        val packageName = sbn.packageName ?: return
        if (packageName !in UPI_PACKAGES) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: text

        // Use the longest text available
        val fullText = if (bigText.length > text.length) bigText else text
        if (fullText.isBlank()) return

        // Extract amount
        val amount = extractAmount(fullText) ?: extractAmount(title) ?: return
        if (amount <= 0) return

        // Determine transaction type
        val txnType = detectTransactionType(fullText + " " + title)

        // Extract counterparty (simple heuristic)
        val counterparty = extractCounterparty(fullText, title)

        val appName = APP_NAMES[packageName] ?: packageName

        val notifData = mapOf(
            "package" to packageName,
            "app_name" to appName,
            "title" to title,
            "text" to fullText,
            "amount" to amount,
            "transaction_type" to txnType,
            "counterparty" to counterparty,
            "timestamp" to System.currentTimeMillis(),
            "category" to "other",
        )

        Log.d(TAG, "💳 UPI notification: $appName | ₹$amount ($txnType) | $counterparty")
        storeNotification(notifData)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // No action needed
    }

    private fun extractAmount(text: String): Double? {
        for (pattern in AMOUNT_PATTERNS) {
            val matcher = pattern.matcher(text)
            if (matcher.find()) {
                val amountStr = matcher.group(1)?.replace(",", "") ?: continue
                return try {
                    amountStr.toDouble()
                } catch (e: NumberFormatException) {
                    null
                }
            }
        }
        return null
    }

    private fun detectTransactionType(text: String): String {
        val lowerText = text.lowercase()
        for (keyword in CREDIT_KEYWORDS) {
            if (lowerText.contains(keyword)) return "credit"
        }
        for (keyword in DEBIT_KEYWORDS) {
            if (lowerText.contains(keyword)) return "debit"
        }
        return "debit" // Default to debit for UPI payments
    }

    private fun extractCounterparty(text: String, title: String): String {
        // Try patterns like "to <name>", "from <name>", "by <name>"
        val patterns = listOf(
            Pattern.compile("(?:to|from|by|paid)\\s+([A-Za-z][\\w\\s]{2,30}?)(?:\\s*[.,!]|$)", Pattern.CASE_INSENSITIVE),
        )
        for (pattern in patterns) {
            val matcher = pattern.matcher(text)
            if (matcher.find()) {
                return matcher.group(1)?.trim() ?: ""
            }
        }
        // Fallback: use title if it looks like a name
        if (title.isNotBlank() && !title.contains("₹") && !title.contains("Rs")) {
            return title.trim()
        }
        return ""
    }

    private fun storeNotification(data: Map<String, Any>) {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val existingJson = prefs.getString(PENDING_NOTIFICATIONS_KEY, "[]") ?: "[]"
            val existingArray = JSONArray(existingJson)

            val obj = JSONObject()
            for ((key, value) in data) {
                obj.put(key, value)
            }
            existingArray.put(obj)

            prefs.edit().putString(PENDING_NOTIFICATIONS_KEY, existingArray.toString()).apply()
            Log.d(TAG, "Stored notification (total pending: ${existingArray.length()})")
        } catch (e: Exception) {
            Log.e(TAG, "Error storing notification: ${e.message}")
        }
    }
}
