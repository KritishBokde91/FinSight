import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/theme.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../widgets/premium_widgets.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<Transaction> _allTransactions = [];
  List<Transaction> _filteredTransactions = [];
  bool _isLoading = true;
  String _selectedPeriod = 'All';
  String _selectedCategory = 'All';
  String _searchQuery = '';

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTransactions() async {
    try {
      final transactions = await ApiService.getTransactions();
      if (mounted) {
        setState(() {
          _allTransactions = transactions;
          _allTransactions.sort(
            (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
          );
          _filterTransactions();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterTransactions() {
    final now = DateTime.now();
    List<Transaction> result = _allTransactions;

    // Period filter
    if (_selectedPeriod != 'All') {
      result = result.where((t) {
        final date = t.date;
        if (date == null) return false;
        if (_selectedPeriod == 'Weekly') {
          return now.difference(date).inDays < 7;
        } else if (_selectedPeriod == 'Monthly') {
          return date.month == now.month && date.year == now.year;
        } else if (_selectedPeriod == 'Yearly') {
          return date.year == now.year;
        }
        return true;
      }).toList();
    }

    // Category filter
    if (_selectedCategory != 'All') {
      result = result.where((t) => t.category == _selectedCategory).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where(
            (t) =>
                t.description.toLowerCase().contains(q) ||
                t.sender.toLowerCase().contains(q) ||
                t.bankName.toLowerCase().contains(q),
          )
          .toList();
    }

    _filteredTransactions = result;
  }

  @override
  Widget build(BuildContext context) {
    // Category totals for filter badges
    final categoryTotals = <String, int>{};
    for (var t in _allTransactions) {
      categoryTotals[t.category] = (categoryTotals[t.category] ?? 0) + 1;
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transactions',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_filteredTransactions.length} of ${_allTransactions.length}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms),

            const SizedBox(height: 16),

            // ── Search Bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.surfaceBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: AppTheme.textMuted,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search transactions...',
                          hintStyle: GoogleFonts.inter(
                            color: AppTheme.textMuted,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                        onChanged: (v) {
                          setState(() {
                            _searchQuery = v;
                            _filterTransactions();
                          });
                        },
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _filterTransactions();
                          });
                        },
                        child: const Icon(
                          Icons.close_rounded,
                          color: AppTheme.textMuted,
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms),

            const SizedBox(height: 12),

            // ── Period Filter ──
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: ['All', 'Weekly', 'Monthly', 'Yearly'].map((period) {
                  final selected = _selectedPeriod == period;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedPeriod = period;
                          _filterTransactions();
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
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
                        child: Text(
                          period,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: selected
                                ? AppTheme.gold
                                : AppTheme.textSecondary,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

            const SizedBox(height: 8),

            // ── Category Filter ──
            if (categoryTotals.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    CategoryChip(
                      category: 'All',
                      selected: _selectedCategory == 'All',
                      onTap: () => setState(() {
                        _selectedCategory = 'All';
                        _filterTransactions();
                      }),
                    ),
                    const SizedBox(width: 8),
                    ...categoryTotals.keys.map(
                      (cat) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: CategoryChip(
                          category: cat,
                          selected: _selectedCategory == cat,
                          onTap: () => setState(() {
                            _selectedCategory = cat;
                            _filterTransactions();
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 300.ms),

            const SizedBox(height: 12),

            // ── Transaction List ──
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.gold),
                    )
                  : _filteredTransactions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: AppTheme.textMuted.withAlpha(100),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No transactions found',
                            style: GoogleFonts.inter(color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchTransactions,
                      color: AppTheme.gold,
                      backgroundColor: AppTheme.surface,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        itemCount: _filteredTransactions.length,
                        itemBuilder: (context, index) {
                          final txn = _filteredTransactions[index];
                          return TransactionTile(
                            description: txn.description,
                            amount: txn.amount.toStringAsFixed(0),
                            date: DateFormat(
                              'MMM d, y',
                            ).format(txn.date ?? DateTime.now()),
                            category: txn.category,
                            isCredit: txn.isCredit,
                            paymentMethod: txn.paymentMethod != 'Other'
                                ? txn.paymentMethod
                                : null,
                          ).animate().fadeIn(
                            duration: 300.ms,
                            delay: Duration(
                              milliseconds: (index * 50).clamp(0, 500),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
