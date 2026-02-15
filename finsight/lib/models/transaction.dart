class Transaction {
  final String id;
  final String sender;
  final double amount;
  final bool isCredit;
  final String description;
  final DateTime? date;
  final String bankName;
  final String paymentMethod;
  final String category;
  final bool categoryEdited;
  final String? receiver;
  final String? counterparty;
  final String? accountNumber;
  final double? anomalyScore;
  final bool isAnomaly;

  Transaction({
    required this.id,
    required this.sender,
    required this.amount,
    required this.isCredit,
    required this.description,
    this.date,
    required this.bankName,
    required this.paymentMethod,
    required this.category,
    this.categoryEdited = false,
    this.receiver,
    this.counterparty,
    this.accountNumber,
    this.anomalyScore,
    this.isAnomaly = false,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    // Handle date parsing from various formats or timestamp
    DateTime? parsedDate;
    if (json['transaction_date'] != null) {
      try {
        // Try ISO format first (from Supabase)
        parsedDate = DateTime.tryParse(json['transaction_date'].toString());
      } catch (_) {}

      if (parsedDate == null) {
        try {
          // Try DD-MM-YYYY
          final parts = (json['transaction_date'] as String).split('-');
          if (parts.length == 3) {
            parsedDate = DateTime(
              int.parse(parts[2]),
              int.parse(parts[1]),
              int.parse(parts[0]),
            );
          }
        } catch (_) {}
      }
    }

    if (parsedDate == null && json['timestamp'] != null) {
      try {
        parsedDate = DateTime.fromMillisecondsSinceEpoch(
          json['timestamp'] is int
              ? json['timestamp']
              : int.parse(json['timestamp'].toString()),
        );
      } catch (_) {}
    }

    final type = json['transaction_type']?.toString().toLowerCase() ?? '';
    final isCredit = type == 'credit';
    final amount = double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0;

    return Transaction(
      id: json['id']?.toString() ?? json['sms_id']?.toString() ?? '',
      sender: json['sender']?.toString() ?? '',
      amount: amount,
      isCredit: isCredit,
      description: json['description']?.toString() ?? json['raw_body'] ?? '',
      date: parsedDate,
      bankName: json['bank_name']?.toString() ?? 'Unknown',
      paymentMethod: json['payment_method']?.toString() ?? 'Other',
      category: json['category']?.toString() ?? 'other',
      categoryEdited: json['category_edited'] == true,
      receiver: json['receiver']?.toString(),
      counterparty: json['counterparty']?.toString(),
      accountNumber: json['account_number']?.toString(),
      anomalyScore: double.tryParse(json['anomaly_score']?.toString() ?? '0'),
      isAnomaly: json['is_anomaly'] == true,
    );
  }
}
