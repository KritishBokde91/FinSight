import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'database_service.dart';

/// Valid labels for the FinSight ML dataset.
const List<String> kValidLabels = [
  'DEBIT_BANK',
  'CREDIT_BANK',
  'UPI_DEBIT',
  'UPI_CREDIT',
  'ATM',
  'NACH_DEBIT',
  'CREDIT_CARD_DEBIT',
  'NON_FINANCIAL',
];

class OllamaService {
  static Future<String> _getHost() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('ollama_host') ?? '10.0.2.2';
    final port = prefs.getString('ollama_port') ?? '11434';
    return 'http://$host:$port';
  }

  static Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ollama_model') ?? 'gemma3:1b';
  }

  /// Tests connectivity to Ollama. Returns list of available models or throws.
  static Future<List<String>> testConnection() async {
    final base = await _getHost();
    final resp = await http.get(Uri.parse('$base/api/tags')).timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    final models = (data['models'] as List).map((m) => m['name'].toString()).toList();
    return models;
  }

  /// Processes a batch of pending SMS and writes AI labels back to DB.
  /// Returns count of successfully labeled SMS.
  static Future<int> processPendingBatch({int batchSize = 10}) async {
    final pendingLabels = await DatabaseService.instance.getPendingAiLabels(limit: batchSize);
    if (pendingLabels.isEmpty) return 0;

    final base = await _getHost();
    final model = await getModel();

    final List<Map<String, dynamic>> promptData = pendingLabels.map((l) => {
      'id': l.id,
      'sms': l.normalizedText,
    }).toList();

    const systemPrompt = '''You are an Indian bank SMS classifier. Classify each SMS into EXACTLY one label.

Labels:
- DEBIT_BANK: bank debit via NEFT/IMPS/RTGS/branch/cheque
- CREDIT_BANK: bank credit, salary received, NEFT/IMPS/RTGS received
- UPI_DEBIT: UPI payment sent (debited via UPI/PhonePe/GPay)
- UPI_CREDIT: UPI payment received
- ATM: ATM cash withdrawal
- NACH_DEBIT: auto-debit/ECS/NACH/EMI mandate executed
- CREDIT_CARD_DEBIT: credit card transaction/spend
- NON_FINANCIAL: OTP, promotional, alert, balance inquiry — NOT a transaction

Return ONLY a JSON array like: [{"id":1,"label":"UPI_DEBIT"},{"id":2,"label":"NON_FINANCIAL"}]
No explanation. No markdown. Only JSON array.
''';

    final userContent = jsonEncode(promptData);

    try {
      final resp = await http.post(
        Uri.parse('$base/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': model,
          'prompt': '$systemPrompt\n\nClassify these:\n$userContent',
          'stream': false,
          'options': {
            'temperature': 0.0,
            'num_predict': 512,
          },
        }),
      ).timeout(const Duration(seconds: 90));

      if (resp.statusCode != 200) {
        debugPrint('Ollama error ${resp.statusCode}: ${resp.body}');
        return 0;
      }

      final data = jsonDecode(resp.body);
      final rawResponse = data['response'] as String? ?? '';

      // Extract JSON array from the response (robust parsing)
      final parsed = _extractJsonArray(rawResponse);
      if (parsed == null) {
        debugPrint('Could not parse JSON from Ollama response: $rawResponse');
        return 0;
      }

      int updated = 0;
      for (var item in parsed) {
        final id = item['id'] as int?;
        final rawLabel = item['label']?.toString().trim().toUpperCase() ?? '';
        // Validate label — fallback to NON_FINANCIAL if unknown
        final label = kValidLabels.contains(rawLabel) ? rawLabel : 'NON_FINANCIAL';

        if (id != null) {
          await DatabaseService.instance.updateAiLabel(id, label, model);
          updated++;
        }
      }
      return updated;
    } catch (e) {
      debugPrint('Ollama request failed: $e');
      return 0;
    }
  }

  static List<dynamic>? _extractJsonArray(String text) {
    // Find the first '[' and last ']' in the response
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start == -1 || end == -1 || end <= start) return null;
    try {
      return jsonDecode(text.substring(start, end + 1)) as List<dynamic>;
    } catch (_) {
      return null;
    }
  }
}
