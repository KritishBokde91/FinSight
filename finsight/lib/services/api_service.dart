import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../models/transaction.dart';

/// Service for communicating with the FinSight backend.
class ApiService {
  /// Post SMS data to the backend in batches.
  /// Returns true if ALL batches succeeded.
  static Future<bool> postSmsData(List<Map<String, dynamic>> smsList) async {
    if (smsList.isEmpty) return true;

    // Split into batches
    for (var i = 0; i < smsList.length; i += AppConstants.batchSize) {
      final end = (i + AppConstants.batchSize < smsList.length)
          ? i + AppConstants.batchSize
          : smsList.length;
      final batch = smsList.sublist(i, end);

      final success = await _postBatch(batch);
      if (!success) return false;
    }
    return true;
  }

  /// Post a single batch with retry logic.
  static Future<bool> _postBatch(List<Map<String, dynamic>> batch) async {
    for (var attempt = 1; attempt <= AppConstants.maxRetries; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse(AppConstants.smsEndpoint),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'data': batch}),
            )
            .timeout(Duration(seconds: AppConstants.apiTimeoutSeconds));

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          print(
            '[ApiService] Batch posted successfully '
            '(${batch.length} items, attempt $attempt) '
            '| txns: ${body['transactions_found'] ?? 0} '
            '| spam: ${body['spam_detected'] ?? 0}',
          );
          return true;
        } else {
          print(
            '[ApiService] Server error ${response.statusCode} on attempt $attempt',
          );
        }
      } catch (e) {
        print('[ApiService] Error on attempt $attempt: $e');
      }

      // Exponential backoff
      if (attempt < AppConstants.maxRetries) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    print('[ApiService] All ${AppConstants.maxRetries} attempts failed');
    return false;
  }

  // ─── Transactions ──────────────────────────────────────────────────

  /// Fetch all processed transactions from the backend.
  static Future<List<Transaction>> getTransactions() async {
    try {
      final response = await http
          .get(Uri.parse('${AppConstants.apiBaseUrl}/api/transactions'))
          .timeout(Duration(seconds: AppConstants.apiTimeoutSeconds));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'] as List<dynamic>? ?? [];
        return data.map((e) => Transaction.fromJson(e)).toList();
      }
    } catch (e) {
      print('[ApiService] Error fetching transactions: $e');
    }
    return [];
  }

  // ─── Analytics ─────────────────────────────────────────────────────

  /// Fetch analytics for a given period.
  static Future<Map<String, dynamic>> getAnalytics({
    String period = 'monthly',
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/analytics?period=$period',
            ),
          )
          .timeout(Duration(seconds: AppConstants.apiTimeoutSeconds));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('[ApiService] Error fetching analytics: $e');
    }
    return {};
  }

  /// Fetch complete analytics summary (all periods).
  static Future<Map<String, dynamic>> getAnalyticsSummary() async {
    try {
      final response = await http
          .get(Uri.parse('${AppConstants.apiBaseUrl}/api/analytics/summary'))
          .timeout(Duration(seconds: AppConstants.apiTimeoutSeconds));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('[ApiService] Error fetching analytics summary: $e');
    }
    return {};
  }

  /// Trigger re-processing of all SMS on the server.
  static Future<Map<String, dynamic>> reprocessAll() async {
    try {
      final response = await http
          .post(Uri.parse('${AppConstants.apiBaseUrl}/api/sms/process'))
          .timeout(Duration(seconds: 120));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('[ApiService] Error reprocessing: $e');
    }
    return {};
  }
}
