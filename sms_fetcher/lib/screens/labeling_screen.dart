import 'package:flutter/material.dart';
import '../models/sms_label.dart';
import '../services/database_service.dart';
import '../services/ollama_service.dart';

class LabelingScreen extends StatefulWidget {
  const LabelingScreen({super.key});
  @override
  State<LabelingScreen> createState() => _LabelingScreenState();
}

class _LabelingScreenState extends State<LabelingScreen> {
  List<SmsLabel> _pending = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final labels = await DatabaseService.instance.getUnreviewedLabels(limit: 50);
    setState(() { _pending = labels; _isLoading = false; });
  }

  Future<void> _confirm(SmsLabel label) async {
    final finalLabel = label.aiLabel ?? label.suggestedLabel;
    await DatabaseService.instance.updateLabelUserFeedback(label.id!, finalLabel, false);
    setState(() => _pending.removeWhere((l) => l.id == label.id));
    if (_pending.isEmpty) _load();
  }

  Future<void> _changeLabel(SmsLabel label) async {
    final newLabel = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select correct label'),
        children: kValidLabels.map((l) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, l),
          child: Text(l),
        )).toList(),
      ),
    );
    if (newLabel != null) {
      await DatabaseService.instance.updateLabelUserFeedback(label.id!, newLabel, true);
      setState(() => _pending.removeWhere((l) => l.id == label.id));
      if (_pending.isEmpty) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Review Labels (${_pending.length} pending)'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pending.isEmpty
              ? const Center(child: Text('All done! No pending labels.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _pending.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final l = _pending[i];
                    final displayLabel = l.aiLabel ?? l.suggestedLabel;
                    return ListTile(
                      isThreeLine: true,
                      title: Text(
                        l.originalText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Row(children: [
                            Text(l.senderId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(width: 8),
                            Text(
                              '${l.timestamp.day}/${l.timestamp.month}/${l.timestamp.year}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Chip(
                            label: Text(displayLabel, style: const TextStyle(fontSize: 11)),
                            backgroundColor: _labelColor(displayLabel).withOpacity(0.2),
                            side: BorderSide(color: _labelColor(displayLabel)),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                          if (l.aiModel != null)
                            Text('by ${l.aiModel}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            tooltip: 'Confirm',
                            onPressed: () => _confirm(l),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.orange),
                            tooltip: 'Change',
                            onPressed: () => _changeLabel(l),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Color _labelColor(String label) {
    switch (label) {
      case 'CREDIT_BANK':
      case 'UPI_CREDIT':
        return Colors.green;
      case 'DEBIT_BANK':
      case 'UPI_DEBIT':
      case 'ATM':
      case 'NACH_DEBIT':
      case 'CREDIT_CARD_DEBIT':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
