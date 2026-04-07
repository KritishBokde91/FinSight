class SmsLabel {
  final int? id;
  final String smsHash;
  final String senderId;
  final DateTime timestamp;
  final String originalText;
  final String normalizedText;
  final String suggestedLabel; // rule-based or AI label (shown in UI)
  final String? aiLabel;       // AI model's label
  final String? aiModel;       // which model labeled it
  final String userLabel;      // final confirmed label by user
  final bool isCorrected;      // true if user changed the AI suggestion

  SmsLabel({
    this.id,
    required this.smsHash,
    required this.senderId,
    required this.timestamp,
    required this.originalText,
    required this.normalizedText,
    required this.suggestedLabel,
    this.aiLabel,
    this.aiModel,
    this.userLabel = '',
    this.isCorrected = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'smsHash': smsHash,
      'senderId': senderId,
      'timestamp': timestamp.toIso8601String(),
      'originalText': originalText,
      'normalizedText': normalizedText,
      'suggestedLabel': suggestedLabel,
      'aiLabel': aiLabel,
      'aiModel': aiModel,
      'userLabel': userLabel,
      'isCorrected': isCorrected ? 1 : 0,
    };
  }

  factory SmsLabel.fromMap(Map<String, dynamic> map) {
    return SmsLabel(
      id: map['id'],
      smsHash: map['smsHash'],
      senderId: map['senderId'],
      timestamp: DateTime.parse(map['timestamp']),
      originalText: map['originalText'],
      normalizedText: map['normalizedText'],
      suggestedLabel: map['suggestedLabel'] ?? 'PENDING',
      aiLabel: map['aiLabel'],
      aiModel: map['aiModel'],
      userLabel: map['userLabel'] ?? '',
      isCorrected: map['isCorrected'] == 1,
    );
  }
}
