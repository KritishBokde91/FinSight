
class PreLabeler {
  static final PreLabeler instance = PreLabeler._init();
  PreLabeler._init();

  String stripPII(String text) {
    String s = text;
    // Account numbers
    s = s.replaceAllMapped(RegExp(r'\b\d{9,18}\b'), (_) => 'XXXX');
    s = s.replaceAllMapped(RegExp(r'A/c\s*(?:no\.?)?\s*\d{6,18}', caseSensitive: false), (_) => 'A/c XXXX');
    // OTPs
    s = s.replaceAllMapped(RegExp(r'\b(?:OTP|One\s*Time\s*Password)\s*(?:is|:)?\s*\d{4,8}\b', caseSensitive: false), (_) => '[OTP]');
    s = s.replaceAllMapped(RegExp(r'\b\d{4,8}\s*is\s*(?:your|the)\s*OTP\b', caseSensitive: false), (_) => '[OTP] is your OTP');
    // Credit cards
    s = s.replaceAllMapped(RegExp(r'\b(?:\d{4}[\s-]?){3}(\d{4})\b'), (m) => 'XXXX-XXXX-XXXX-${m.group(1)}');
    // Phone numbers
    s = s.replaceAllMapped(RegExp(r'\b[6-9]\d{9}\b'), (m) => 'XXXXXX${m.group(0)!.substring(6)}');
    return s;
  }

  /// Rule-based pre-label returning one of the 8 FinSight classes.
  /// This runs immediately on insert; AI will refine later.
  String suggestLabel(String text) {
    final t = text.toLowerCase();

    // Non-financial first
    if (t.contains('otp') || t.contains('one time password') ||
        t.contains('do not share') || t.contains('valid for')) {
      return 'NON_FINANCIAL';
    }

    // ATM
    if (t.contains('atm') && (t.contains('withdraw') || t.contains('cash'))) {
      return 'ATM';
    }

    // Credit card
    if ((t.contains('credit card') || t.contains('cc ') || t.contains('card ending')) &&
        (t.contains('spent') || t.contains('debited') || t.contains('transaction'))) {
      return 'CREDIT_CARD_DEBIT';
    }

    // NACH / EMI / mandate
    if (t.contains('nach') || t.contains('ecs') || t.contains('mandate') ||
        t.contains('emi') || t.contains('auto-debit') || t.contains('autopay') ||
        t.contains('standing instruction')) {
      return 'NACH_DEBIT';
    }

    // UPI
    if (t.contains('upi') || t.contains('@') ||
        t.contains('phonepay') || t.contains('gpay') || t.contains('paytm')) {
      if (t.contains('credited') || t.contains('received') || t.contains('credit')) {
        return 'UPI_CREDIT';
      }
      return 'UPI_DEBIT';
    }

    // Bank credit
    if (t.contains('credited') || t.contains('received') ||
        t.contains('deposited') || t.contains('salary') || t.contains('neft cr') ||
        t.contains('imps cr') || t.contains('rtgs cr')) {
      return 'CREDIT_BANK';
    }

    // Bank debit
    if (t.contains('debited') || t.contains('deducted') ||
        t.contains('neft') || t.contains('imps') || t.contains('rtgs') ||
        t.contains('transferred') || t.contains('paid to')) {
      return 'DEBIT_BANK';
    }

    // Default
    return 'NON_FINANCIAL';
  }
}
