import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/sms_label.dart';
import 'database_service.dart';
import 'pre_labeler.dart';

class SmsService {
  static final SmsQuery query = SmsQuery();

  static Future<bool> requestPermission() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  static Future<int> fetchAndStoreSms() async {
    final permissionGranted = await requestPermission();
    if (!permissionGranted) return 0;

    final messages = await query.querySms(
      kinds: [SmsQueryKind.inbox],
      count: 2000, 
    );

    int newSmsCount = 0;

    for (var message in messages) {
      if (message.address == null || message.body == null || message.date == null) {
        continue;
      }
      
      final sender = message.address!;
      final text = message.body!;
      final timestamp = message.date!;

      // Simple filter: Bank sender IDs typically are 6 letters/alphanumeric, often ending in "BK", "INB" etc, or containing "Bank"
      // Wait, SMS typically have senders without phone numbers for commercial bulk SMS (Format: XY-ABCDEF)
      // We will check if it contains numbers. Commercial SMS senders usually don't contain digits or are purely alphabetical IDs.
      // But we'll just check if the sender length is < 15 and contains letters.
      if (!RegExp(r'[a-zA-Z]').hasMatch(sender)) continue; // Filter out personal phone numbers

      // Hash generation for unique check
      final String rawInput = '$sender:$text:${timestamp.toIso8601String()}';
      final String hash = sha256.convert(utf8.encode(rawInput)).toString();

      final normalizedText = PreLabeler.instance.stripPII(text);


      final label = SmsLabel(
        smsHash: hash,
        senderId: sender,
        timestamp: timestamp,
        originalText: text,
        normalizedText: normalizedText,
        suggestedLabel: 'Pending',
      );

      try {
        final id = await DatabaseService.instance.insertLabel(label);
        if (id > 0) newSmsCount++;
      } catch (e) {
        // Assume duplicate or db error, just continue
      }
    }

    return newSmsCount;
  }
}
