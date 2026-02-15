import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/sms_service.dart';
import 'services/api_service.dart';
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundService.initialize();
  runApp(const FinSightApp());
}

class FinSightApp extends StatelessWidget {
  const FinSightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FinSight',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _status = 'Initializing...';
  bool _isSyncing = false;
  int _totalSynced = 0;
  int _transactionsFound = 0;
  int _spamDetected = 0;

  // Analytics data
  Map<String, dynamic> _analytics = {};
  List<Map<String, dynamic>> _transactions = [];
  String _selectedPeriod = 'monthly';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Request permissions
    final smsStatus = await Permission.sms.request();
    final notifStatus = await Permission.notification.request();

    if (!smsStatus.isGranted) {
      setState(() => _status = '❌ SMS permission denied');
      return;
    }

    setState(() => _status = 'Permissions granted ✓');

    // Start background service
    await BackgroundService.start();

    // Initial sync
    await _syncSms();

    // Fetch analytics
    await _fetchAnalytics();
  }

  Future<void> _syncSms() async {
    setState(() {
      _isSyncing = true;
      _status = 'Syncing SMS...';
    });

    try {
      final isFirstRun = await SmsService.isFirstRun();

      List<Map<String, dynamic>> smsList;
      if (isFirstRun) {
        setState(() => _status = 'First run — reading all SMS...');
        smsList = await SmsService.fetchAllSms();
      } else {
        final lastSync = await SmsService.getLastSyncTimestamp();
        setState(() => _status = 'Reading new SMS...');
        smsList = await SmsService.fetchNewSms(lastSync);
      }

      if (smsList.isNotEmpty) {
        setState(() => _status = 'Sending ${smsList.length} SMS to server...');
        final success = await ApiService.postSmsData(smsList);

        if (success) {
          await SmsService.saveLastSyncTimestamp();
          if (isFirstRun) await SmsService.markFirstRunDone();
          setState(() {
            _totalSynced = smsList.length;
            _status = '✅ Synced ${smsList.length} SMS';
          });
        } else {
          setState(() => _status = '⚠️ Sync failed — will retry');
        }
      } else {
        setState(() => _status = '✅ Already up to date');
      }

      // Process pending native SMS (from SmsReceiver when app was killed)
      final pending = await SmsService.getPendingNativeSms();
      if (pending.isNotEmpty) {
        await ApiService.postSmsData(pending);
        await SmsService.clearPendingNativeSms();
      }
    } catch (e) {
      setState(() => _status = '❌ Error: $e');
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  Future<void> _resyncAll() async {
    setState(() {
      _isSyncing = true;
      _status = 'Re-syncing ALL SMS...';
    });

    try {
      final smsList = await SmsService.fetchAllSms();
      setState(() => _status = 'Sending ${smsList.length} SMS to server...');
      final success = await ApiService.postSmsData(smsList);

      if (success) {
        await SmsService.saveLastSyncTimestamp();
        setState(() {
          _totalSynced = smsList.length;
          _status = '✅ Re-synced ${smsList.length} SMS';
        });

        // Fetch updated results
        await _fetchAnalytics();
      } else {
        setState(() => _status = '⚠️ Re-sync failed');
      }
    } catch (e) {
      setState(() => _status = '❌ Error: $e');
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  Future<void> _fetchAnalytics() async {
    try {
      final analytics = await ApiService.getAnalytics(period: _selectedPeriod);
      final transactions = await ApiService.getTransactions();

      setState(() {
        _analytics = analytics;
        _transactions = transactions;
        if (analytics.isNotEmpty) {
          final summary = analytics['summary'] as Map<String, dynamic>? ?? {};
          _transactionsFound = summary['total_transactions'] as int? ?? 0;
        }
      });
    } catch (e) {
      print('[HomePage] Error fetching analytics: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _analytics['summary'] as Map<String, dynamic>? ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'FinSight',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isSyncing ? null : _fetchAnalytics,
            tooltip: 'Refresh analytics',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAnalytics,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Status Card ──
              _buildStatusCard(theme),
              const SizedBox(height: 16),

              // ── Quick Actions ──
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.sync,
                      label: 'Sync New',
                      onTap: _isSyncing ? null : _syncSms,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.cloud_sync,
                      label: 'Re-sync All',
                      onTap: _isSyncing ? null : _resyncAll,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Summary Cards ──
              if (summary.isNotEmpty) ...[
                Text(
                  'Financial Summary',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildSummaryCard(
                      '💰 Income',
                      '₹${_formatAmount(summary['total_credit_amount'] ?? 0)}',
                      Colors.green,
                      '${summary['total_credits'] ?? 0} transactions',
                    ),
                    const SizedBox(width: 12),
                    _buildSummaryCard(
                      '💸 Expense',
                      '₹${_formatAmount(summary['total_debit_amount'] ?? 0)}',
                      Colors.red,
                      '${summary['total_debits'] ?? 0} transactions',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildNetFlowCard(summary, theme),
                const SizedBox(height: 24),

                // ── Period Selector ──
                Text(
                  'Analytics Period',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildPeriodSelector(),
                const SizedBox(height: 16),

                // ── Period Breakdown ──
                _buildPeriodBreakdown(theme),
                const SizedBox(height: 24),

                // ── Payment Methods ──
                _buildPaymentMethods(theme),
                const SizedBox(height: 24),
              ],

              // ── Recent Transactions ──
              if (_transactions.isNotEmpty) ...[
                Text(
                  'Recent Transactions',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ..._transactions.take(20).map((t) => _buildTransactionTile(t)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (_isSyncing)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.sms, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_status, style: theme.textTheme.bodyLarge),
                  if (_totalSynced > 0)
                    Text(
                      '$_totalSynced SMS synced',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  Expanded _buildSummaryCard(
    String title,
    String amount,
    Color color,
    String subtitle,
  ) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Text(
                amount,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetFlowCard(Map<String, dynamic> summary, ThemeData theme) {
    final net = (summary['net_flow'] as num? ?? 0).toDouble();
    final isPositive = net >= 0;

    return Card(
      color: isPositive
          ? Colors.green.withOpacity(0.15)
          : Colors.red.withOpacity(0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Net Flow', style: theme.textTheme.titleMedium),
            Text(
              '${isPositive ? '+' : ''}₹${_formatAmount(net)}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isPositive ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    const periods = ['weekly', 'monthly', 'quarterly', 'yearly'];
    return SegmentedButton<String>(
      segments: periods
          .map(
            (p) => ButtonSegment(
              value: p,
              label: Text(
                p[0].toUpperCase() + p.substring(1),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          )
          .toList(),
      selected: {_selectedPeriod},
      onSelectionChanged: (val) {
        setState(() => _selectedPeriod = val.first);
        _fetchAnalytics();
      },
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }

  Widget _buildPeriodBreakdown(ThemeData theme) {
    final periods = _analytics['period_breakdown'] as List<dynamic>? ?? [];
    if (periods.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Period Breakdown',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...periods.reversed.take(6).map((p) {
          final period = p as Map<String, dynamic>;
          final credit = (period['credit_amount'] as num? ?? 0).toDouble();
          final debit = (period['debit_amount'] as num? ?? 0).toDouble();
          final net = credit - debit;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    period['period'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '↑ ₹${_formatAmount(credit)}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '↓ ₹${_formatAmount(debit)}',
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                      Text(
                        '${net >= 0 ? '+' : ''}₹${_formatAmount(net)}',
                        style: TextStyle(
                          color: net >= 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPaymentMethods(ThemeData theme) {
    final methods =
        _analytics['payment_methods'] as Map<String, dynamic>? ?? {};
    if (methods.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Methods',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: methods.entries.take(6).map((e) {
            final data = e.value as Map<String, dynamic>;
            return Chip(
              avatar: const Icon(Icons.payment, size: 16),
              label: Text(
                '${e.key}: ${data['count']} (₹${_formatAmount(data['amount'] ?? 0)})',
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> txn) {
    final amount = (txn['amount'] as num?)?.toDouble() ?? 0;
    final type = txn['transaction_type'] as String? ?? '?';
    final isCredit = type == 'credit';
    final bank = txn['bank_name'] as String? ?? '';
    final method = txn['payment_method'] as String? ?? '';
    final counterparty = txn['counterparty'] as String? ?? '';
    final date = txn['transaction_date'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: isCredit
              ? Colors.green.withValues(alpha: 0.2)
              : Colors.red.withValues(alpha: 0.2),
          child: Icon(
            isCredit ? Icons.arrow_downward : Icons.arrow_upward,
            color: isCredit ? Colors.green : Colors.red,
            size: 20,
          ),
        ),
        title: Text(
          '${isCredit ? '+' : '-'}₹${_formatAmount(amount)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isCredit ? Colors.green : Colors.red,
          ),
        ),
        subtitle: Text(
          [
            if (counterparty.isNotEmpty) counterparty,
            if (bank.isNotEmpty) bank,
            if (method.isNotEmpty) 'via $method',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: Colors.grey[400]),
        ),
        trailing: date.isNotEmpty
            ? Text(
                date,
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              )
            : null,
      ),
    );
  }

  String _formatAmount(dynamic amount) {
    final num val = (amount is num) ? amount : 0;
    if (val >= 10000000) return '${(val / 10000000).toStringAsFixed(1)}Cr';
    if (val >= 100000) return '${(val / 100000).toStringAsFixed(1)}L';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(1)}K';
    return val.toStringAsFixed(val == val.roundToDouble() ? 0 : 2);
  }
}
