import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../services/sms_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  bool _isSyncing = false;
  Map<String, dynamic> _analyticsSummary = {};
  List<Transaction> _recentTransactions = [];
  String _lastSyncTime = 'Never';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchAnalytics(),
      _fetchRecentTransactions(),
      _loadSyncTime(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchAnalytics() async {
    try {
      final data = await ApiService.getAnalyticsSummary();
      if (mounted) setState(() => _analyticsSummary = data);
    } catch (e) {
      print('Error fetching analytics: $e');
    }
  }

  Future<void> _fetchRecentTransactions() async {
    try {
      final txns = await ApiService.getTransactions();
      //Sort by date desc and take top 5
      txns.sort(
        (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
      );
      if (mounted) setState(() => _recentTransactions = txns.take(5).toList());
    } catch (e) {
      print('Error fetching transactions: $e');
    }
  }

  Future<void> _loadSyncTime() async {
    final ts = await SmsService.getLastSyncTimestamp();
    if (ts > 0) {
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      if (mounted) {
        setState(() {
          _lastSyncTime = DateFormat('MMM d, h:mm a').format(date);
        });
      }
    }
  }

  Future<void> _syncSms() async {
    setState(() => _isSyncing = true);
    try {
      final lastSync = await SmsService.getLastSyncTimestamp();
      final newSms = await SmsService.fetchNewSms(lastSync);
      if (newSms.isNotEmpty) {
        await ApiService.postSmsData(newSms);
        await SmsService.saveLastSyncTimestamp();
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Synced ${newSms.length} new SMS')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No new SMS found')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final monthly = _analyticsSummary['monthly']?['summary'] ?? {};
    final income = (monthly['total_credit_amount'] ?? 0).toDouble();
    final expense = (monthly['total_debit_amount'] ?? 0).toDouble();
    final net = income - expense;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // status card
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Sync Status'),
              subtitle: Text('Last synced: $_lastSyncTime'),
              trailing: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _syncSms,
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // Summary Cards
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  title: 'Income',
                  amount: income,
                  color: Colors.green,
                  icon: Icons.arrow_downward,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                  title: 'Expense',
                  amount: expense,
                  color: Colors.red,
                  icon: Icons.arrow_upward,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              title: const Text('Net Flow'),
              trailing: Text(
                '₹${net.toStringAsFixed(2)}',
                style: TextStyle(
                  color: net >= 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'Recent Transactions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          ..._recentTransactions.map(
            (txn) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: txn.isCredit
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.red.withValues(alpha: 0.2),
                  child: Icon(
                    txn.isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                    color: txn.isCredit ? Colors.green : Colors.red,
                    size: 20,
                  ),
                ),
                title: Text(
                  txn.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  DateFormat('MMM d').format(txn.date ?? DateTime.now()),
                ),
                trailing: Text(
                  '₹${txn.amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: txn.isCredit ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(color: color)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '₹${amount.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
