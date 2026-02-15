import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../models/transaction.dart';
import 'auth_service.dart';

/// Service for communicating with the FinSight backend.
/// All API calls include user_id for user-scoped data.
class ApiService {
  /// Get the current user's ID for API calls.
  static Future<String?> _getUserId() async {
    return await AuthService.getUserId();
  }

  /// Post SMS data to the backend in batches.
  /// Returns true if ALL batches succeeded.
  static Future<bool> postSmsData(List<Map<String, dynamic>> smsList) async {
    if (smsList.isEmpty) return true;
    final userId = await _getUserId();

    // Split into batches
    for (var i = 0; i < smsList.length; i += AppConstants.batchSize) {
      final end = (i + AppConstants.batchSize < smsList.length)
          ? i + AppConstants.batchSize
          : smsList.length;
      final batch = smsList.sublist(i, end);

      final success = await _postBatch(batch, userId);
      if (!success) return false;
    }
    return true;
  }

  /// Post a single batch with retry logic.
  static Future<bool> _postBatch(
    List<Map<String, dynamic>> batch,
    String? userId,
  ) async {
    for (var attempt = 1; attempt <= AppConstants.maxRetries; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse(AppConstants.smsEndpoint),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'data': batch, 'user_id': userId}),
            )
            .timeout(Duration(seconds: AppConstants.apiTimeoutSeconds));

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          debugPrint(
            '[ApiService] Batch posted successfully '
            '(${batch.length} items, attempt $attempt) '
            '| txns: ${body['transactions_found'] ?? 0} '
            '| spam: ${body['spam_detected'] ?? 0}',
          );
          return true;
        } else {
          debugPrint(
            '[ApiService] Server error ${response.statusCode} on attempt $attempt',
          );
        }
      } catch (e) {
        debugPrint('[ApiService] Error on attempt $attempt: $e');
      }

      // Exponential backoff
      if (attempt < AppConstants.maxRetries) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    debugPrint('[ApiService] All ${AppConstants.maxRetries} attempts failed');
    return false;
  }

  // ─── Transactions ──────────────────────────────────────────────────

  /// Fetch all processed transactions from the backend.
  static Future<List<Transaction>> getTransactions() async {
    try {
      final userId = await _getUserId();
      final uri = userId != null
          ? '${AppConstants.apiBaseUrl}/api/transactions?user_id=$userId'
          : '${AppConstants.apiBaseUrl}/api/transactions';

      final response = await http
          .get(Uri.parse(uri))
          .timeout(Duration(seconds: AppConstants.apiTimeoutSeconds));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'] as List<dynamic>? ?? [];
        return data.map((e) => Transaction.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('[ApiService] Error fetching transactions: $e');
    }
    return [];
  }

  // ─── Analytics ─────────────────────────────────────────────────────

  /// Fetch analytics for a given period.
  static Future<Map<String, dynamic>> getAnalytics({
    String period = 'monthly',
  }) async {
    try {
      final userId = await _getUserId();
      var url = '${AppConstants.apiBaseUrl}/api/analytics?period=$period';
      if (userId != null) url += '&user_id=$userId';

      final response = await http
          .get(Uri.parse(url))
          .timeout(Duration(seconds: AppConstants.apiTimeoutSeconds));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[ApiService] Error fetching analytics: $e');
    }
    return {};
  }

  /// Fetch complete analytics summary (all periods).
  static Future<Map<String, dynamic>> getAnalyticsSummary() async {
    try {
      final userId = await _getUserId();
      var url = '${AppConstants.apiBaseUrl}/api/analytics/summary';
      if (userId != null) url += '?user_id=$userId';

      final response = await http
          .get(Uri.parse(url))
          .timeout(Duration(seconds: AppConstants.apiTimeoutSeconds));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[ApiService] Error fetching analytics summary: $e');
    }
    return {};
  }

  /// Trigger re-processing of all SMS on the server.
  static Future<Map<String, dynamic>> reprocessAll() async {
    try {
      final response = await http
          .post(Uri.parse('${AppConstants.apiBaseUrl}/api/sms/process'))
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[ApiService] Error reprocessing: $e');
    }
    return {};
  }
}
