import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database_service.dart';

class ExportService {
  /// Exports ALL SMS (labeled or not) as a raw CSV for external AI labeling.
  static Future<String> exportAllRaw() async {
    final labels = await DatabaseService.instance.getAllLabels();

    List<List<dynamic>> rows = [];

    // Header
    rows.add([
      'id',
      'sender_id',
      'timestamp',
      'normalized_text',  // PII-stripped SMS text
      'label',            // blank — to be filled by AI
    ]);

    for (var label in labels) {
      rows.add([
        label.id ?? '',
        label.senderId,
        label.timestamp.toIso8601String(),
        label.normalizedText,
        '', // label column intentionally empty — AI will fill this
      ]);
    }

    final csv = const CsvEncoder().convert(rows);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/sms_unlabeled_${DateTime.now().millisecondsSinceEpoch}.csv';
    await File(path).writeAsString(csv);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: 'Unlabeled SMS dataset — ${labels.length} rows. Use the AI prompt to label the "label" column.',
      ),
    );

    return path;
  }

  /// Exports only rows that have a label (ai_label or user_label) — final training dataset.
  static Future<String> exportLabeled() async {
    final labels = await DatabaseService.instance.getAllLabels();

    List<List<dynamic>> rows = [];
    rows.add([
      'id',
      'sender_id',
      'timestamp',
      'normalized_text',
      'label',
      'was_corrected',
    ]);

    for (var label in labels) {
      final finalLabel = label.userLabel.isNotEmpty
          ? label.userLabel
          : (label.aiLabel ?? '');
      if (finalLabel.isEmpty) continue;

      rows.add([
        label.id ?? '',
        label.senderId,
        label.timestamp.toIso8601String(),
        label.normalizedText,
        finalLabel,
        label.isCorrected ? '1' : '0',
      ]);
    }

    final csv = const CsvEncoder().convert(rows);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/sms_labeled_${DateTime.now().millisecondsSinceEpoch}.csv';
    await File(path).writeAsString(csv);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: 'Labeled SMS dataset — ${rows.length - 1} rows ready for training.',
      ),
    );

    return path;
  }
}
