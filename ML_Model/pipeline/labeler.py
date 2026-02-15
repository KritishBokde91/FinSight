"""
labeler.py — Dynamic Auto-Labeler for Indian SMS
=================================================
This is NOT trained on any single user's data. It uses universal patterns
that work across ALL Indian banks, wallets, UPI apps, and telecom providers.

Labels:
  financial_transaction  — actual credit/debit movement of money
  financial_alert        — balance inquiry, card statement, EMI reminder (no money moved)
  otp                    — one-time passwords
  promotional            — offers, ads, subscriptions, marketing
  personal               — person-to-person messages
  spam                   — phishing, fraud attempts
"""

import re
from typing import Dict, Tuple

# ─── UNIVERSAL INDIAN FINANCIAL PATTERNS ──────────────────────────────────
# These cover ALL Indian banks, not just specific ones.

# Comprehensive list of Indian bank sender code patterns
BANK_SENDER_PATTERNS = re.compile(
    r'(?i)(SBI|HDFC|ICICI|AXIS|KOTAK|BOB|PNB|UNION|CANARA|CENTBK|IPPB|'
    r'IDBI|INDBNK|FEDERAL|BARODA|SYNDCT|ANDHRA|ALLAHABAD|UCO|IOB|'
    r'MAHABK|DENABNK|VIJAYA|CORPBNK|INDUSIND|YESBNK|BANDHAN|RBL|'
    r'CITI|HSBC|STANCHART|AMEX|PAYTM|PHONEPE|GPAY|AMAZONPAY|'
    r'BAJFIN|TATACAP|MUTHOOT|MANAPPURAM|LICHFL|'
    r'SBIUPI|HDFCUPI|ICICUPI|AXISUPI|BOBUPI|PNBUPI|'
    r'SBICRD|HDFCCC|ICICICC|AXISCC|KOTAKCC|'
    r'SBIBNK|HDFCBN|ICICBN|AXISBN)',
    re.IGNORECASE
)

# ─── AMOUNT PATTERNS (Indian currency) ───────────────────────────────────
AMOUNT_PATTERN = re.compile(
    r'(?:Rs\.?|INR|₹)\s*[\d,]+(?:\.\d{1,2})?'
    r'|[\d,]+(?:\.\d{1,2})?\s*(?:Rs\.?|INR|₹)',
    re.IGNORECASE
)

# ─── TRANSACTION INDICATORS ──────────────────────────────────────────────
CREDIT_INDICATORS = re.compile(
    r'(?i)\b(credited|credit|received|deposited|added|refund(?:ed)?|'
    r'cashback|reversed|cr\b)',
    re.IGNORECASE
)

DEBIT_INDICATORS = re.compile(
    r'(?i)\b(debited|debit|withdrawn|spent|paid|transferred|'
    r'purchase|charged|dr\b)',
    re.IGNORECASE
)

# ─── ACCOUNT PATTERNS ────────────────────────────────────────────────────
ACCOUNT_PATTERN = re.compile(
    r'(?i)(?:a/?c|account|acct|card)\s*(?:no\.?|number|#|ending)?\s*'
    r'[:\s]*[Xx*]*\s*\d{3,}',
    re.IGNORECASE
)

# ─── UPI / PAYMENT METHOD PATTERNS ───────────────────────────────────────
UPI_PATTERN = re.compile(r'(?i)\bUPI\b|VPA|@\w+bank|@\w+psp', re.IGNORECASE)
NEFT_PATTERN = re.compile(r'(?i)\bNEFT\b', re.IGNORECASE)
IMPS_PATTERN = re.compile(r'(?i)\bIMPS\b', re.IGNORECASE)
RTGS_PATTERN = re.compile(r'(?i)\bRTGS\b', re.IGNORECASE)
CARD_PATTERN = re.compile(
    r'(?i)\b(card|debit\s*card|credit\s*card|ATM|POS|swipe)\b',
    re.IGNORECASE
)
WALLET_PATTERN = re.compile(
    r'(?i)\b(wallet|paytm|phonepe|gpay|amazon\s*pay|freecharge|mobikwik)\b',
    re.IGNORECASE
)

# ─── OTP PATTERN ─────────────────────────────────────────────────────────
OTP_PATTERN = re.compile(
    r'(?i)\b(OTP|one.?time|verification\s*code|'
    r'security\s*code|pin\s*is|code\s*is|password\s*is)\b',
    re.IGNORECASE
)

# ─── BALANCE PATTERN ─────────────────────────────────────────────────────
BALANCE_PATTERN = re.compile(
    r'(?i)\b(balance|bal|avl\.?\s*bal|available\s*bal(?:ance)?|'
    r'outstanding|total\s*(?:amt|amount)\s*due|min\s*(?:amt|amount)\s*due)\b',
    re.IGNORECASE
)

# ─── SPAM / PHISHING INDICATORS ──────────────────────────────────────────
SPAM_INDICATORS = re.compile(
    r'(?i)(congratulations.*won|winner|lottery|crore.*prize|'
    r'lakh.*prize|claim\s*now|lucky\s*draw|free\s*gift|'
    r'urgent.*kyc.*expire|suspend.*account.*click|'
    r'verify.*immediately.*link)',
    re.IGNORECASE
)

# ─── PROMOTIONAL INDICATORS ──────────────────────────────────────────────
PROMO_INDICATORS = re.compile(
    r'(?i)(offer|discount|sale|cashback\s*up\s*to|off\s*on|'
    r'subscribe|install\s*now|download|'
    r'coupon|voucher|flat\s*\d+%|upto\s*\d+%|'
    r'exclusive|limited\s*time|special\s*offer|'
    r'free\s*trial|premium\s*free|unlock)',
    re.IGNORECASE
)

# ─── NON-TRANSACTIONAL FINANCIAL SMS ─────────────────────────────────────
# These contain financial language but are NOT actual transactions
NON_TRANSACTION_FINANCIAL = re.compile(
    r'(?i)(statement.*generated|statement.*ready|'
    r'emi\s*reminder|payment\s*reminder|'
    r'payment\s*due|overdue|'
    r'credit\s*score|cibil|'
    r'insurance.*renew|policy.*expire|'
    r'loan\s*(?:offer|approved|eligible)|'
    r'pre.?approved|'
    r'upgrade\s*(?:card|limit)|'
    r'increase.*limit|'
    r'reward\s*points)',
    re.IGNORECASE
)


def label_sms(body: str, sender: str = "") -> Tuple[str, str, float]:
    """
    Classify a single SMS and return (label, sub_label, confidence).
    
    This works on ANY Indian SMS regardless of bank or format.
    Uses a priority-based cascade: spam → OTP → transaction → financial_alert → promo → personal.
    
    Returns:
        tuple: (label, sub_label, confidence_score)
            - label: 'financial_transaction', 'financial_alert', 'otp', 
                     'promotional', 'personal', 'spam'
            - sub_label: more specific type (e.g., 'credit', 'debit', 'bill_payment')
            - confidence: 0.0 - 1.0
    """
    body_lower = body.lower().strip()
    sender_upper = sender.upper().strip()
    
    # ── 1. SPAM DETECTION (highest priority) ──
    if SPAM_INDICATORS.search(body):
        return ('spam', 'phishing', 0.90)
    
    # ── 2. OTP DETECTION ──
    if OTP_PATTERN.search(body):
        # OTPs with amounts are sometimes transaction OTPs
        if AMOUNT_PATTERN.search(body) and (CREDIT_INDICATORS.search(body) or DEBIT_INDICATORS.search(body)):
            pass  # Fall through to transaction detection
        else:
            return ('otp', 'verification', 0.95)
    
    # ── 3. TRANSACTION DETECTION ──
    has_amount = bool(AMOUNT_PATTERN.search(body))
    has_account = bool(ACCOUNT_PATTERN.search(body))
    has_credit = bool(CREDIT_INDICATORS.search(body))
    has_debit = bool(DEBIT_INDICATORS.search(body))
    is_bank_sender = bool(BANK_SENDER_PATTERNS.search(sender_upper))
    has_upi = bool(UPI_PATTERN.search(body))
    has_neft = bool(NEFT_PATTERN.search(body))
    has_imps = bool(IMPS_PATTERN.search(body))
    has_balance = bool(BALANCE_PATTERN.search(body))
    
    # Strong transaction signals
    transaction_score = 0
    if has_amount: transaction_score += 0.25
    if has_account: transaction_score += 0.20
    if has_credit or has_debit: transaction_score += 0.30
    if is_bank_sender: transaction_score += 0.15
    if has_upi or has_neft or has_imps: transaction_score += 0.10
    
    # Check if this is a NON-TRANSACTIONAL financial SMS
    is_non_transaction = bool(NON_TRANSACTION_FINANCIAL.search(body))
    
    if transaction_score >= 0.50 and not is_non_transaction:
        # Determine sub-type
        if has_credit and not has_debit:
            sub_label = 'credit'
        elif has_debit and not has_credit:
            sub_label = 'debit'
        elif has_credit and has_debit:
            # Both present — look at context
            credit_pos = CREDIT_INDICATORS.search(body).start()
            debit_pos = DEBIT_INDICATORS.search(body).start()
            sub_label = 'debit' if debit_pos < credit_pos else 'credit'
        else:
            # Has amount + account but no clear direction
            sub_label = 'unknown_direction'
        
        return ('financial_transaction', sub_label, min(transaction_score + 0.10, 1.0))
    
    # ── 4. FINANCIAL ALERT (non-transaction) ──
    financial_alert_score = 0
    if is_bank_sender: financial_alert_score += 0.30
    if has_amount: financial_alert_score += 0.15
    if has_balance: financial_alert_score += 0.20
    if is_non_transaction: financial_alert_score += 0.25
    if has_account: financial_alert_score += 0.10
    
    if financial_alert_score >= 0.40:
        # Determine alert sub-type
        if 'statement' in body_lower:
            sub_label = 'statement'
        elif 'emi' in body_lower or 'payment due' in body_lower or 'overdue' in body_lower:
            sub_label = 'payment_reminder'
        elif 'balance' in body_lower or 'bal' in body_lower:
            sub_label = 'balance_info'
        elif 'block' in body_lower or 'suspend' in body_lower:
            sub_label = 'security_alert'
        else:
            sub_label = 'general_alert'
        
        return ('financial_alert', sub_label, min(financial_alert_score + 0.10, 1.0))
    
    # ── 5. PROMOTIONAL ──
    if PROMO_INDICATORS.search(body):
        return ('promotional', 'marketing', 0.80)
    
    # ── 6. PERSONAL SMS (fallback) ──
    # If sender is a phone number (not a shortcode), likely personal
    if re.match(r'^\+?\d{10,}$', sender):
        return ('personal', 'p2p_message', 0.70)
    
    # Default: promotional/informational
    return ('promotional', 'informational', 0.60)


def label_sms_batch(sms_list: list) -> list:
    """
    Label a batch of SMS messages. Each SMS should have 'body' and 'address' keys.
    
    Returns list of dicts with original SMS data + label, sub_label, confidence.
    """
    results = []
    for sms in sms_list:
        body = sms.get('body', '')
        sender = sms.get('address', '')
        label, sub_label, confidence = label_sms(body, sender)
        
        labeled = dict(sms)
        labeled['label'] = label
        labeled['sub_label'] = sub_label
        labeled['label_confidence'] = round(confidence, 3)
        results.append(labeled)
    
    return results
