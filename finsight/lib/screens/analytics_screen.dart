import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  List<Transaction> _transactions = [];
  bool _isLoading = true;
  // String _selectedPeriod = 'Weekly';

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
      return const Center(child: CircularProgressIndicator());
    }

    final data = _processData_Weekly();

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Period Selector (simplified for now)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Expense Trend (Last 7 Days)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Chart
            AspectRatio(
              aspectRatio: 1.5,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: data.isEmpty
                      ? 100
                      : data
                                .map((e) => e.value)
                                .reduce((a, b) => a > b ? a : b) *
                            1.2,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 &&
                              value.toInt() < data.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                data[value.toInt()].label,
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return const Text('');
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
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: data.asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.value,
                          color: Colors.redAccent,
                          width: 16,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 20),
            // Income vs Expense Pie (Optional, maybe later)
          ],
        ),
      ),
    );
  }

  List<_ChartData> _processData_Weekly() {
    final now = DateTime.now();
    // Last 7 days including today
    final days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));

    return days.map((day) {
      final dailyTxns = _transactions.where((t) {
        final tDate = t.date;
        return tDate != null &&
            !t.isCredit && // Expenses only
            tDate.year == day.year &&
            tDate.month == day.month &&
            tDate.day == day.day;
      });

      final total = dailyTxns.fold(0.0, (sum, t) => sum + t.amount);

      // Label: Mon, Tue, etc.
      // Basic weekday name
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final label = weekdays[day.weekday - 1];

      return _ChartData(label, total);
    }).toList();
  }
}

class _ChartData {
  final String label;
  final double value;
  _ChartData(this.label, this.value);
}
