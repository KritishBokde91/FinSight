import 'dart:async';
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/sms_service.dart';
import '../services/export_service.dart';
import '../services/ollama_service.dart';
import 'labeling_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, int> _stats = {};
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isLabeling = false;
  String _aiStatus = '';
  int _totalLabeled = 0;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadStats(showSpinner: true);
    // Poll DB every 2 seconds — quietly updates numbers in real-time
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _loadStats();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// [showSpinner] = true only on first load. Silent refresh otherwise.
  Future<void> _loadStats({bool showSpinner = false}) async {
    if (showSpinner) setState(() => _isLoading = true);
    final stats = await DatabaseService.instance.getStats();
    if (mounted) {
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  Future<void> _syncSms() async {
    setState(() => _isSyncing = true);
    final count = await SmsService.fetchAndStoreSms();
    setState(() => _isSyncing = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count new SMS imported.')),
      );
    }
    // Timer will auto-refresh stats. Start AI labeling if needed.
    if (count > 0 && !_isLabeling) _runAiLabeling();
  }

  Future<void> _runAiLabeling() async {
    if (_isLabeling) return;
    final model = await OllamaService.getModel();
    setState(() {
      _isLabeling = true;
      _totalLabeled = 0;
      _aiStatus = 'Starting $model...';
    });

    int consecutiveFails = 0;

    while (true) {
      // Read pending count directly from current stats (updated by timer)
      final pendingAi = _stats['pending_ai'] ?? 0;
      if (pendingAi == 0) break;

      if (mounted) {
        setState(() => _aiStatus =
            '$model — labeled $_totalLabeled, $pendingAi remaining');
      }

      final labeled = await OllamaService.processPendingBatch(batchSize: 10);
      if (labeled > 0) {
        _totalLabeled += labeled;
        consecutiveFails = 0;
        // Immediately refresh stats after each batch (in addition to timer)
        await _loadStats();
      } else {
        consecutiveFails++;
        if (consecutiveFails >= 3) {
          if (mounted) {
            setState(() => _aiStatus =
                'Ollama error after $_totalLabeled labeled. Check Settings.');
          }
          break;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    if (mounted) {
      setState(() {
        _isLabeling = false;
        _aiStatus = _totalLabeled > 0
            ? 'Done — $_totalLabeled SMS labeled by AI.'
            : _aiStatus;
      });
    }
    await _loadStats();
  }

  Future<void> _exportRaw() async {
    try {
      await ExportService.exportAllRaw();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _exportLabeled() async {
    try {
      await ExportService.exportLabeled();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PrivacySMS — Dataset Builder'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ).then((_) => _loadStats()),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Real-time stats table
                  Table(
                    border: TableBorder.all(color: Colors.grey.shade300),
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(1)
                    },
                    children: [
                      _tableRow('Total SMS', '${_stats['total'] ?? 0}',
                          header: true),
                      _tableRow('AI Labeled', '${_stats['ai_labeled'] ?? 0}'),
                      _tableRow('Pending AI', '${_stats['pending_ai'] ?? 0}',
                          highlight: (_stats['pending_ai'] ?? 0) > 0),
                      _tableRow(
                          'User Reviewed', '${_stats['reviewed'] ?? 0}'),
                      _tableRow('Pending Review',
                          '${_stats['pending_review'] ?? 0}'),
                    ],
                  ),

                  // AI status row — always visible when labeling
                  const SizedBox(height: 12),
                  if (_aiStatus.isNotEmpty)
                    Row(
                      children: [
                        if (_isLabeling) ...[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            _aiStatus,
                            style: TextStyle(
                              fontSize: 13,
                              color: _aiStatus.contains('error') ||
                                      _aiStatus.contains('Check')
                                  ? Colors.red
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),

                  const Spacer(),

                  // Action buttons
                  ElevatedButton.icon(
                    onPressed: _isSyncing ? null : _syncSms,
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync),
                    label:
                        Text(_isSyncing ? 'Syncing...' : 'Sync Inbox'),
                  ),
                  const SizedBox(height: 8),

                  ElevatedButton.icon(
                    onPressed: _isLabeling ? null : _runAiLabeling,
                    icon: _isLabeling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.smart_toy),
                    label: Text(
                        _isLabeling ? 'AI Labeling...' : 'Run AI Labeling'),
                  ),
                  const SizedBox(height: 8),

                  ElevatedButton.icon(
                    onPressed: (_stats['pending_review'] ?? 0) > 0
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LabelingScreen()),
                            ).then((_) => _loadStats())
                        : null,
                    icon: const Icon(Icons.swipe),
                    label: const Text('Review / Correct Labels'),
                  ),
                  const SizedBox(height: 8),

                  OutlinedButton.icon(
                    onPressed: _exportRaw,
                    icon: const Icon(Icons.upload_file),
                    label: Text('Export ALL SMS (${_stats['total'] ?? 0} rows) — for AI labeling'),
                  ),
                  const SizedBox(height: 8),

                  OutlinedButton.icon(
                    onPressed: _exportLabeled,
                    icon: const Icon(Icons.download),
                    label: Text('Export Labeled Only (${_stats['ai_labeled'] ?? 0} rows)'),
                  ),
                ],
              ),
            ),
    );
  }

  TableRow _tableRow(String label, String value,
      {bool header = false, bool highlight = false}) {
    final style = TextStyle(
      fontWeight: header ? FontWeight.bold : FontWeight.normal,
      color: highlight ? Colors.orange.shade800 : null,
    );
    return TableRow(
      decoration:
          header ? BoxDecoration(color: Colors.grey.shade100) : null,
      children: [
        Padding(
            padding: const EdgeInsets.all(8),
            child: Text(label, style: style)),
        Padding(
            padding: const EdgeInsets.all(8),
            child: Text(value,
                style: style, textAlign: TextAlign.center)),
      ],
    );
  }
}
