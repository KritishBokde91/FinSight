import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<Transaction> _allTransactions = [];
  List<Transaction> _filteredTransactions = [];
  bool _isLoading = true;
  String _selectedPeriod = 'All'; // All, Weekly, Monthly, Yearly

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    try {
      final transactions = await ApiService.getTransactions();
      if (mounted) {
        setState(() {
          _allTransactions = transactions;
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
    setState(() {
      if (_selectedPeriod == 'All') {
        _filteredTransactions = _allTransactions;
      } else {
        _filteredTransactions = _allTransactions.where((t) {
          final date = t.date; // Ensure Transaction model has DateTime date
          if (date == null) return false;

          if (_selectedPeriod == 'Weekly') {
            final weekStart = now.subtract(Duration(days: now.weekday - 1));
            return date.isAfter(weekStart.subtract(const Duration(seconds: 1)));
          } else if (_selectedPeriod == 'Monthly') {
            return date.month == now.month && date.year == now.year;
          } else if (_selectedPeriod == 'Yearly') {
            return date.year == now.year;
          }
          return true;
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', 'Weekly', 'Monthly', 'Yearly'].map((period) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: FilterChip(
                    label: Text(period),
                    selected: _selectedPeriod == period,
                    onSelected: (selected) {
                      if (mounted) {
                        setState(() {
                          _selectedPeriod = period;
                          _filterTransactions();
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredTransactions.isEmpty
          ? const Center(child: Text('No transactions found'))
          : ListView.builder(
              itemCount: _filteredTransactions.length,
              itemBuilder: (context, index) {
                final txn = _filteredTransactions[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: txn.isCredit
                        ? Colors.green.shade100
                        : Colors.red.shade100,
                    child: Icon(
                      txn.isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                      color: txn.isCredit ? Colors.green : Colors.red,
                    ),
                  ),
                  title: Text(txn.description),
                  subtitle: Text(
                    DateFormat('MMM d, y').format(txn.date ?? DateTime.now()),
                  ),
                  trailing: Text(
                    '${txn.isCredit ? '+' : '-'} ₹${txn.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: txn.isCredit ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
