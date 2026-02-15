import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/theme.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../services/sms_service.dart';
import '../widgets/premium_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
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
      debugPrint('Error fetching analytics: $e');
    }
  }

  Future<void> _fetchRecentTransactions() async {
    try {
      final txns = await ApiService.getTransactions();
      txns.sort(
        (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
      );
      if (mounted) setState(() => _recentTransactions = txns.take(5).toList());
    } catch (e) {
      debugPrint('Error fetching transactions: $e');
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
            SnackBar(
              content: Text('✨ Synced ${newSms.length} new SMS'),
              backgroundColor: AppTheme.surfaceLight,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All up to date'),
              backgroundColor: AppTheme.surfaceLight,
            ),
          );
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
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.gold),
      );
    }

    final monthly = _analyticsSummary['monthly']?['summary'] ?? {};
    final income = (monthly['total_credit_amount'] ?? 0).toDouble();
    final expense = (monthly['total_debit_amount'] ?? 0).toDouble();
    final net = income - expense;

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.gold,
      backgroundColor: AppTheme.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          // ── Header ──
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FinSight',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    DateFormat('EEEE, MMMM d').format(DateTime.now()),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Sync button
              _buildSyncButton(),
            ],
          ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),

          const SizedBox(height: 24),

          // ── Net Flow Hero ──
          _buildNetFlowCard(net, income, expense)
              .animate()
              .fadeIn(duration: 500.ms, delay: 100.ms)
              .slideY(begin: 0.1),

          const SizedBox(height: 16),

          // ── Income & Expense Cards ──
          Row(
            children: [
              Expanded(
                child:
                    MetricCard(
                          title: 'Income',
                          value: '₹${_formatAmount(income)}',
                          icon: Icons.south_west_rounded,
                          color: AppTheme.success,
                          subtitle: 'This month',
                        )
                        .animate()
                        .fadeIn(duration: 500.ms, delay: 200.ms)
                        .slideX(begin: -0.1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child:
                    MetricCard(
                          title: 'Expense',
                          value: '₹${_formatAmount(expense)}',
                          icon: Icons.north_east_rounded,
                          color: AppTheme.error,
                          subtitle: 'This month',
                        )
                        .animate()
                        .fadeIn(duration: 500.ms, delay: 300.ms)
                        .slideX(begin: 0.1),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Recent Transactions ──
          const SectionHeader(
            title: 'Recent Transactions',
          ).animate().fadeIn(duration: 400.ms, delay: 400.ms),

          const SizedBox(height: 8),

          if (_recentTransactions.isEmpty)
            _buildEmptyState()
          else
            ..._recentTransactions.asMap().entries.map((entry) {
              final txn = entry.value;
              return TransactionTile(
                    description: txn.description,
                    amount: txn.amount.toStringAsFixed(0),
                    date: DateFormat(
                      'MMM d',
                    ).format(txn.date ?? DateTime.now()),
                    category: txn.category,
                    isCredit: txn.isCredit,
                    paymentMethod: txn.paymentMethod != 'Other'
                        ? txn.paymentMethod
                        : null,
                  )
                  .animate()
                  .fadeIn(
                    duration: 400.ms,
                    delay: Duration(milliseconds: 500 + entry.key * 100),
                  )
                  .slideX(begin: 0.05);
            }),
        ],
      ),
    );
  }

  Widget _buildSyncButton() {
    return GestureDetector(
      onTap: _isSyncing ? null : _syncSms,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.surfaceBorder),
          boxShadow: AppTheme.cardShadow,
        ),
        child: _isSyncing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.gold,
                ),
              )
            : Column(
                children: [
                  const Icon(
                    Icons.sync_rounded,
                    color: AppTheme.gold,
                    size: 22,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sync',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildNetFlowCard(double net, double income, double expense) {
    final isPositive = net >= 0;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPositive
              ? [const Color(0xFF0D2818), const Color(0xFF0A1F14)]
              : [const Color(0xFF2D1111), const Color(0xFF1F0A0A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppTheme.cardRadius,
        border: Border.all(
          color: isPositive
              ? AppTheme.success.withAlpha(40)
              : AppTheme.error.withAlpha(40),
        ),
        boxShadow: [
          BoxShadow(
            color: (isPositive ? AppTheme.success : AppTheme.error).withAlpha(
              20,
            ),
            blurRadius: 30,
            spreadRadius: -5,
          ),
          ...AppTheme.cardShadow,
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPositive
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                color: isPositive ? AppTheme.success : AppTheme.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Net Flow',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                'Synced: $_lastSyncTime',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${isPositive ? '+' : ''}₹${_formatAmount(net.abs())}',
            style: GoogleFonts.outfit(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: isPositive ? AppTheme.success : AppTheme.error,
            ),
          ),
          const SizedBox(height: 12),
          // Mini progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (income + expense) > 0 ? income / (income + expense) : 0.5,
              backgroundColor: AppTheme.error.withAlpha(40),
              valueColor: AlwaysStoppedAnimation(
                AppTheme.success.withAlpha(180),
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '↓ ₹${_formatAmount(income)}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.success,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '↑ ₹${_formatAmount(expense)}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(
            Icons.inbox_rounded,
            size: 48,
            color: AppTheme.textMuted.withAlpha(100),
          ),
          const SizedBox(height: 12),
          Text(
            'No transactions yet',
            style: GoogleFonts.inter(color: AppTheme.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap sync to get started',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textMuted.withAlpha(150),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 10000000) {
      return '${(amount / 10000000).toStringAsFixed(2)}Cr';
    } else if (amount >= 100000) {
      return '${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }
}
