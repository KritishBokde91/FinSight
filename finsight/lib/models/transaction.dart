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
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    // Handle date parsing from various formats or timestamp
    DateTime? parsedDate;
    if (json['transaction_date'] != null) {
      try {
        // Try parsing DD-MM-YYYY first
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
      id: json['sms_id']?.toString() ?? '',
      sender: json['sender']?.toString() ?? '',
      amount: amount,
      isCredit: isCredit,
      description: json['description']?.toString() ?? json['raw_body'] ?? '',
      date: parsedDate,
      bankName: json['bank_name']?.toString() ?? 'Unknown',
      paymentMethod: json['payment_method']?.toString() ?? 'Other',
      category: json['sub_label']?.toString() ?? 'General',
    );
  }
}
