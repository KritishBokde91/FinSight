package com.genzloop.finsight

import android.content.ContentResolver
import android.database.Cursor
import android.net.Uri
import android.provider.Telephony
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayList
import java.util.HashMap

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.genzloop.finsight/sms"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAllSms" -> {
                    val smsList = getAllSms()
                    result.success(smsList)
                }
                "getSmsSince" -> {
                    val timestamp = call.argument<Long>("timestamp") ?: 0L
                    val smsList = getSmsSince(timestamp)
                    result.success(smsList)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getAllSms(): List<Map<String, String>> {
        val smsList = ArrayList<Map<String, String>>()
        val contentResolver: ContentResolver = contentResolver
        val uri: Uri = Telephony.Sms.CONTENT_URI
        val cursor: Cursor? = contentResolver.query(uri, null, null, null, "date DESC")

        cursor?.use {
            if (it.moveToFirst()) {
                do {
                    val smsData = HashMap<String, String>()
                    for (i in 0 until it.columnCount) {
                        val columnName = it.getColumnName(i)
                        val value = it.getString(i)
                        smsData[columnName] = value ?: ""
                    }
                    smsList.add(smsData)
                } while (it.moveToNext())
            }
        }
        return smsList
    }

    private fun getSmsSince(timestamp: Long): List<Map<String, String>> {
        val smsList = ArrayList<Map<String, String>>()
        val contentResolver: ContentResolver = contentResolver
        val uri: Uri = Telephony.Sms.CONTENT_URI
        val selection = "${Telephony.Sms.DATE} > ?"
        val selectionArgs = arrayOf(timestamp.toString())
        val cursor: Cursor? = contentResolver.query(uri, null, selection, selectionArgs, "date ASC")

        cursor?.use {
            if (it.moveToFirst()) {
                do {
                    val smsData = HashMap<String, String>()
                    for (i in 0 until it.columnCount) {
                        val columnName = it.getColumnName(i)
                        val value = it.getString(i)
                        smsData[columnName] = value ?: ""
                    }
                    smsList.add(smsData)
                } while (it.moveToNext())
            }
        }
        return smsList
    }
}
