import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/theme.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../widgets/premium_widgets.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  List<Transaction> _transactions = [];
  bool _isLoading = true;
  String _selectedPeriod = 'Monthly';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final txns = await ApiService.getTransactions();
      if (mounted) {
        setState(() {
          _transactions = txns;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.gold),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchData,
          color: AppTheme.gold,
          backgroundColor: AppTheme.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              // ── Header ──
              Text(
                'Analytics',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: 16),

              // ── Period Selector ──
              _buildPeriodSelector().animate().fadeIn(
                duration: 400.ms,
                delay: 100.ms,
              ),

              const SizedBox(height: 24),

              // ── Spending Trend (Bar Chart) ──
              const SectionHeader(
                title: 'Spending Trend',
              ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
              const SizedBox(height: 8),
              _buildSpendingTrend().animate().fadeIn(
                duration: 500.ms,
                delay: 300.ms,
              ),

              const SizedBox(height: 24),

              // ── Category Breakdown (Donut) ──
              const SectionHeader(
                title: 'By Category',
              ).animate().fadeIn(duration: 400.ms, delay: 400.ms),
              const SizedBox(height: 8),
              _buildCategoryDonut().animate().fadeIn(
                duration: 500.ms,
                delay: 500.ms,
              ),

              const SizedBox(height: 24),

              // ── Income vs Expense (Line Chart) ──
              const SectionHeader(
                title: 'Income vs Expense',
              ).animate().fadeIn(duration: 400.ms, delay: 600.ms),
              const SizedBox(height: 8),
              _buildIncomeExpenseTrend().animate().fadeIn(
                duration: 500.ms,
                delay: 700.ms,
              ),

              const SizedBox(height: 24),

              // ── Payment Methods (Horizontal Bar) ──
              const SectionHeader(
                title: 'Payment Methods',
              ).animate().fadeIn(duration: 400.ms, delay: 800.ms),
              const SizedBox(height: 8),
              _buildPaymentMethods().animate().fadeIn(
                duration: 500.ms,
                delay: 900.ms,
              ),

              const SizedBox(height: 24),

              // ── Top Merchants ──
              const SectionHeader(
                title: 'Top Merchants',
              ).animate().fadeIn(duration: 400.ms, delay: 1000.ms),
              const SizedBox(height: 8),
              _buildTopMerchants().animate().fadeIn(
                duration: 500.ms,
                delay: 1100.ms,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Row(
      children: ['Weekly', 'Monthly', 'Quarterly', 'Yearly'].map((period) {
        final selected = _selectedPeriod == period;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedPeriod = period),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.gold.withAlpha(20)
                    : AppTheme.surfaceLight,
                borderRadius: AppTheme.chipRadius,
                border: Border.all(
                  color: selected
                      ? AppTheme.gold.withAlpha(100)
                      : AppTheme.surfaceBorder,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                period,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: selected ? AppTheme.gold : AppTheme.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  List<Transaction> _getFilteredByPeriod() {
    final now = DateTime.now();
    return _transactions.where((t) {
      final d = t.date;
      if (d == null) return false;
      switch (_selectedPeriod) {
        case 'Weekly':
          return now.difference(d).inDays < 7;
        case 'Monthly':
          return d.month == now.month && d.year == now.year;
        case 'Quarterly':
          return now.difference(d).inDays < 90;
        case 'Yearly':
          return d.year == now.year;
      }
      return true;
    }).toList();
  }

  // ── Spending Trend Bar Chart ──────────────────────────────────────
  Widget _buildSpendingTrend() {
    final filtered = _getFilteredByPeriod();
    final debits = filtered.where((t) => !t.isCredit).toList();

    // Group by date
    final Map<String, double> dailySpend = {};
    for (var t in debits) {
      final key = t.date != null ? '${t.date!.month}/${t.date!.day}' : 'N/A';
      dailySpend[key] = (dailySpend[key] ?? 0) + t.amount;
    }

    final entries = dailySpend.entries.toList();
    if (entries.isEmpty) return _emptyChart('No expense data');

    final maxY =
        entries.map((e) => e.value).reduce((a, b) => a > b ? a : b) * 1.2;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.skeuCard,
      child: AspectRatio(
        aspectRatio: 1.6,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY,
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                tooltipRoundedRadius: 8,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  return BarTooltipItem(
                    '₹${rod.toY.toStringAsFixed(0)}',
                    GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    if (value.toInt() >= 0 && value.toInt() < entries.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          entries[value.toInt()].key,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) => FlLine(
                color: AppTheme.surfaceBorder.withAlpha(50),
                strokeWidth: 0.5,
              ),
            ),
            borderData: FlBorderData(show: false),
            barGroups: entries.asMap().entries.map((e) {
              return BarChartGroupData(
                x: e.key,
                barRods: [
                  BarChartRodData(
                    toY: e.value.value,
                    gradient: AppTheme.expenseGradient,
                    width: entries.length > 15 ? 8 : 16,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ── Category Donut Chart ──────────────────────────────────────────
  Widget _buildCategoryDonut() {
    final filtered = _getFilteredByPeriod();
    final debits = filtered.where((t) => !t.isCredit).toList();

    final Map<String, double> catSpend = {};
    for (var t in debits) {
      catSpend[t.category] = (catSpend[t.category] ?? 0) + t.amount;
    }

    if (catSpend.isEmpty) return _emptyChart('No category data');

    final total = catSpend.values.reduce((a, b) => a + b);
    final sorted = catSpend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.skeuCard,
      child: Row(
        children: [
          // Donut chart
          SizedBox(
            width: 140,
            height: 140,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 35,
                sections: sorted.map((e) {
                  final color =
                      AppTheme.categoryColors[e.key] ?? AppTheme.textMuted;
                  return PieChartSectionData(
                    value: e.value,
                    color: color,
                    radius: 30,
                    showTitle: false,
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 20),
          // Legend
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sorted.take(6).map((e) {
                final pct = (e.value / total * 100).toStringAsFixed(0);
                final color =
                    AppTheme.categoryColors[e.key] ?? AppTheme.textMuted;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${e.key[0].toUpperCase()}${e.key.substring(1)}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        '$pct%',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Income vs Expense Line Chart ──────────────────────────────────
  Widget _buildIncomeExpenseTrend() {
    final filtered = _getFilteredByPeriod();

    // Group by date
    final Map<String, double> dailyIncome = {};
    final Map<String, double> dailyExpense = {};

    for (var t in filtered) {
      if (t.date == null) continue;
      final key = '${t.date!.month}/${t.date!.day}';
      if (t.isCredit) {
        dailyIncome[key] = (dailyIncome[key] ?? 0) + t.amount;
      } else {
        dailyExpense[key] = (dailyExpense[key] ?? 0) + t.amount;
      }
    }

    final allDates = {...dailyIncome.keys, ...dailyExpense.keys}.toList()
      ..sort();
    if (allDates.isEmpty) return _emptyChart('No data available');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.skeuCard,
      child: AspectRatio(
        aspectRatio: 1.6,
        child: LineChart(
          LineChartData(
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(tooltipRoundedRadius: 8),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) => FlLine(
                color: AppTheme.surfaceBorder.withAlpha(50),
                strokeWidth: 0.5,
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: (allDates.length / 5).ceilToDouble().clamp(
                    1,
                    double.infinity,
                  ),
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx >= 0 && idx < allDates.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          allDates[idx],
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              // Income line
              LineChartBarData(
                spots: allDates.asMap().entries.map((e) {
                  return FlSpot(e.key.toDouble(), dailyIncome[e.value] ?? 0);
                }).toList(),
                isCurved: true,
                color: AppTheme.success,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppTheme.success.withAlpha(20),
                ),
              ),
              // Expense line
              LineChartBarData(
                spots: allDates.asMap().entries.map((e) {
                  return FlSpot(e.key.toDouble(), dailyExpense[e.value] ?? 0);
                }).toList(),
                isCurved: true,
                color: AppTheme.error,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppTheme.error.withAlpha(20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Payment Methods Breakdown ─────────────────────────────────────
  Widget _buildPaymentMethods() {
    final filtered = _getFilteredByPeriod();
    final Map<String, double> methodSpend = {};
    final Map<String, int> methodCount = {};

    for (var t in filtered) {
      if (!t.isCredit) {
        methodSpend[t.paymentMethod] =
            (methodSpend[t.paymentMethod] ?? 0) + t.amount;
        methodCount[t.paymentMethod] = (methodCount[t.paymentMethod] ?? 0) + 1;
      }
    }

    if (methodSpend.isEmpty) return _emptyChart('No payment data');

    final sorted = methodSpend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = sorted.first.value;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.skeuCard,
      child: Column(
        children: sorted.map((e) {
          final pct = e.value / maxVal;
          final count = methodCount[e.key] ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      e.key,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '₹${e.value.toStringAsFixed(0)} ($count)',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: AppTheme.surfaceBorder.withAlpha(50),
                    valueColor: AlwaysStoppedAnimation(
                      AppTheme.cyan.withAlpha(180),
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Top Merchants ─────────────────────────────────────────────────
  Widget _buildTopMerchants() {
    final filtered = _getFilteredByPeriod();
    final Map<String, double> merchantSpend = {};

    for (var t in filtered) {
      if (!t.isCredit) {
        final name = t.description.length > 30
            ? t.description.substring(0, 30)
            : t.description;
        merchantSpend[name] = (merchantSpend[name] ?? 0) + t.amount;
      }
    }

    if (merchantSpend.isEmpty) return _emptyChart('No merchant data');

    final sorted = merchantSpend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.skeuCard,
      child: Column(
        children: sorted.take(8).toList().asMap().entries.map((entry) {
          final e = entry.value;
          final rank = entry.key + 1;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rank <= 3
                        ? AppTheme.gold.withAlpha(20)
                        : AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#$rank',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: rank <= 3 ? AppTheme.gold : AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    e.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '₹${e.value.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.error,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _emptyChart(String message) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: AppTheme.skeuCard,
      child: Center(
        child: Text(
          message,
          style: GoogleFonts.inter(color: AppTheme.textMuted),
        ),
      ),
    );
  }
}
