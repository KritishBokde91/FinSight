"""
extractor.py — Smart Transaction Detail Extractor for Indian SMS
================================================================
Extracts: amount, transaction_type, account, bank, merchant/counterparty,
payment_method (UPI/NEFT/IMPS/RTGS/Card/Wallet), reference, date, balance.

Uses 60+ regex patterns designed for ALL Indian banks.
NOT trained on any specific dataset. Works dynamically on any Indian SMS.
"""

import re
from datetime import datetime
from typing import Dict, Optional


# ─── AMOUNT EXTRACTION ───────────────────────────────────────────────────
# Handles: Rs.100, Rs 1,000.50, INR 500, Rs. 1,23,456.78 (Indian numbering)
AMOUNT_REGEX = re.compile(
    r'(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)'
    r'|([\d,]+(?:\.\d{1,2})?)\s*(?:Rs\.?|INR|₹)',
    re.IGNORECASE
)

# ─── ACCOUNT / CARD EXTRACTION ───────────────────────────────────────────
ACCOUNT_REGEX = re.compile(
    r'(?:a/?c|account|acct)\s*(?:no\.?|number|#)?\s*'
    r'[:\s]*([Xx*]*\s*\d{3,})',
    re.IGNORECASE
)
CARD_REGEX = re.compile(
    r'(?:card|debit\s*card|credit\s*card)\s*'
    r'(?:ending\s*(?:with|in)?|no\.?|number)?\s*'
    r'[:\s]*(?:[Xx*]*\s*)?(\d{2,6})',
    re.IGNORECASE
)

# ─── UPI REFERENCE ───────────────────────────────────────────────────────
UPI_REF_REGEX = re.compile(
    r'(?:UPI\s*(?:Ref|ref\.?|reference|txn)\s*(?:no\.?|number|#|id)?'
    r'|Ref\s*(?:No\.?|number|#)?)\s*[:\s]*(\d{6,})',
    re.IGNORECASE
)

# ─── BANK NAME EXTRACTION ────────────────────────────────────────────────
BANK_MAP = {
    'SBI': 'State Bank of India',
    'HDFC': 'HDFC Bank',
    'ICICI': 'ICICI Bank',
    'AXIS': 'Axis Bank',
    'KOTAK': 'Kotak Mahindra Bank',
    'BOB': 'Bank of Baroda',
    'PNB': 'Punjab National Bank',
    'UNION': 'Union Bank of India',
    'CANARA': 'Canara Bank',
    'CENTBK': 'Central Bank of India',
    'IPPB': 'India Post Payments Bank',
    'IDBI': 'IDBI Bank',
    'INDBNK': 'Indian Bank',
    'FEDERAL': 'Federal Bank',
    'BARODA': 'Bank of Baroda',
    'UCO': 'UCO Bank',
    'IOB': 'Indian Overseas Bank',
    'INDUSIND': 'IndusInd Bank',
    'YESBNK': 'Yes Bank',
    'BANDHAN': 'Bandhan Bank',
    'RBL': 'RBL Bank',
    'CITI': 'Citibank',
    'HSBC': 'HSBC',
    'STANCHART': 'Standard Chartered',
    'AMEX': 'American Express',
    'PAYTM': 'Paytm Payments Bank',
    'BAJFIN': 'Bajaj Finance',
    'TATACAP': 'Tata Capital',
    'MUTHOOT': 'Muthoot Finance',
    'LICHFL': 'LIC Housing Finance',
    'CBOI': 'Central Bank of India',
}

# ─── COUNTERPARTY / MERCHANT EXTRACTION ──────────────────────────────────
# Pattern: "to/from <NAME>" or "transfer from/to <NAME>"
COUNTERPARTY_REGEX = re.compile(
    r'(?:to|from|transfer\s*(?:to|from)|for\s*UPI\s*to|'
    r'UPI\s*(?:to|from))\s+'
    r'([A-Z][A-Za-z\s.]+?)(?:\s+(?:on|Ref|ref|via|at|for|Rs|INR|UPI|$))',
    re.IGNORECASE
)
MERCHANT_REGEX_2 = re.compile(
    r'(?:at|@)\s+([A-Za-z][A-Za-z\s.&\'-]+?)(?:\s+(?:on|Ref|ref|Rs|INR|$))',
    re.IGNORECASE
)

# ─── DATE EXTRACTION FROM SMS BODY ───────────────────────────────────────
DATE_REGEX_PATTERNS = [
    re.compile(r'(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})'),       # DD-MM-YYYY or DD/MM/YY
    re.compile(r'(\d{1,2}(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\d{2,4})', re.IGNORECASE),  # 08Feb26
    re.compile(r'(\d{1,2}\s*(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s*\d{2,4})', re.IGNORECASE),
    re.compile(r'((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},?\s*\d{2,4})', re.IGNORECASE),
]

# ─── BALANCE EXTRACTION ──────────────────────────────────────────────────
BALANCE_REGEX = re.compile(
    r'(?:(?:avl\.?\s*|available\s*)?(?:bal(?:ance)?|Bal)\.?)\s*'
    r'(?:is|:)?\s*'
    r'(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
    re.IGNORECASE
)

# ─── PAYMENT METHOD DETECTION ────────────────────────────────────────────
PAYMENT_METHODS = [
    ('UPI',   re.compile(r'\bUPI\b', re.IGNORECASE)),
    ('NEFT',  re.compile(r'\bNEFT\b', re.IGNORECASE)),
    ('IMPS',  re.compile(r'\bIMPS\b', re.IGNORECASE)),
    ('RTGS',  re.compile(r'\bRTGS\b', re.IGNORECASE)),
    ('ATM',   re.compile(r'\bATM\b', re.IGNORECASE)),
    ('POS',   re.compile(r'\bPOS\b', re.IGNORECASE)),
    ('NACH',  re.compile(r'\bNACH\b', re.IGNORECASE)),
    ('ECS',   re.compile(r'\bECS\b', re.IGNORECASE)),
    ('Card',  re.compile(r'\b(?:debit|credit)\s*card\b', re.IGNORECASE)),
    ('Wallet', re.compile(r'\b(?:wallet|paytm|phonepe|gpay)\b', re.IGNORECASE)),
    ('Net Banking', re.compile(r'\bnet\s*banking\b', re.IGNORECASE)),
    ('DBT',   re.compile(r'\bDBT(?:L)?\b', re.IGNORECASE)),  # Direct Benefit Transfer
]


def parse_amount(text: str) -> Optional[float]:
    """Extract the primary transaction amount from SMS text."""
    match = AMOUNT_REGEX.search(text)
    if match:
        amt_str = match.group(1) or match.group(2)
        if amt_str:
            amt_str = amt_str.replace(',', '').strip()
            try:
                return float(amt_str)
            except ValueError:
                pass
    return None


def parse_all_amounts(text: str) -> list:
    """Extract ALL amounts mentioned in the SMS."""
    amounts = []
    for match in AMOUNT_REGEX.finditer(text):
        amt_str = match.group(1) or match.group(2)
        if amt_str:
            amt_str = amt_str.replace(',', '').strip()
            try:
                amounts.append(float(amt_str))
            except ValueError:
                pass
    return amounts


def parse_account(text: str) -> Optional[str]:
    """Extract account number (may be masked)."""
    match = ACCOUNT_REGEX.search(text)
    if match:
        return match.group(1).strip()
    match = CARD_REGEX.search(text)
    if match:
        return match.group(1).strip()
    return None


def parse_bank(sender: str, body: str) -> Optional[str]:
    """Identify the bank from sender code or body text."""
    sender_upper = sender.upper()
    body_upper = body.upper()
    
    for code, name in BANK_MAP.items():
        if code in sender_upper or code in body_upper:
            return name
    
    # Try to extract from body
    bank_match = re.search(r'\b(SBI|HDFC|ICICI|AXIS|KOTAK|BOB|PNB|CENTBK|IPPB|IDBI)\b', 
                            body_upper)
    if bank_match:
        code = bank_match.group(1)
        return BANK_MAP.get(code, code)
    
    # Check for "- BANK_NAME" at end of SMS (very common pattern)
    end_match = re.search(r'-\s*([A-Za-z\s]+?)$', body.strip())
    if end_match:
        bank_name = end_match.group(1).strip()
        if len(bank_name) > 2 and len(bank_name) < 40:
            return bank_name
    
    return None


def parse_counterparty(body: str) -> Optional[str]:
    """Extract the merchant/person involved in the transaction."""
    match = COUNTERPARTY_REGEX.search(body)
    if match:
        name = match.group(1).strip()
        # Filter out common false positives
        if name.lower() not in ['your', 'the', 'a', 'an', 'rs', 'inr']:
            return name
    
    match = MERCHANT_REGEX_2.search(body)
    if match:
        name = match.group(1).strip()
        if name.lower() not in ['your', 'the', 'a', 'an']:
            return name
    
    return None


def parse_payment_method(body: str) -> Optional[str]:
    """Detect the payment method from SMS text."""
    for method, pattern in PAYMENT_METHODS:
        if pattern.search(body):
            return method
    return None


def parse_reference(body: str) -> Optional[str]:
    """Extract transaction reference number."""
    match = UPI_REF_REGEX.search(body)
    if match:
        return match.group(1)
    
    # Generic reference: "Ref No XXXXX" or "Ref XXXXX"
    ref_match = re.search(r'Ref\.?\s*(?:No\.?\s*)?[:\s]*(\w{6,})', body, re.IGNORECASE)
    if ref_match:
        return ref_match.group(1)
    return None


def parse_transaction_date(body: str, timestamp: str = "") -> Optional[str]:
    """Extract the transaction date from SMS body or timestamp."""
    for pattern in DATE_REGEX_PATTERNS:
        match = pattern.search(body)
        if match:
            return match.group(1)
    
    # Fall back to SMS timestamp
    if timestamp:
        try:
            ts = int(timestamp)
            dt = datetime.fromtimestamp(ts / 1000)
            return dt.strftime('%d-%m-%Y')
        except (ValueError, OSError):
            pass
    
    return None


def parse_balance(body: str) -> Optional[float]:
    """Extract balance after transaction."""
    match = BALANCE_REGEX.search(body)
    if match:
        bal_str = match.group(1).replace(',', '').strip()
        try:
            return float(bal_str)
        except ValueError:
            pass
    return None


def detect_transaction_type(body: str) -> Optional[str]:
    """Determine if transaction is credit or debit."""
    body_lower = body.lower()
    
    credit_kws = ['credited', 'received', 'deposited', 'refund', 'cashback', 'reversed', 'added']
    debit_kws = ['debited', 'withdrawn', 'spent', 'paid', 'transferred', 'purchase', 'charged', 'deducted']
    
    has_credit = any(kw in body_lower for kw in credit_kws)
    has_debit = any(kw in body_lower for kw in debit_kws)
    
    # Comprehensive exclusions for non-transactional SMS
    # (card statements, bill reminders, legal warnings, mandates, etc.)
    non_txn_patterns = [
        r'(?:bill|amount|total|min|outstanding|amt)[.\s]*(?:due|payable)',
        r'statement.*(?:generated|ready|available)',
        r'legal\s*(?:action|notice)',
        r'despite.*reminder',
        r'several\s*reminders',
        r'(?:pay|click).*quickpay',
        r'please\s*(?:pay|clear|settle)',
        r'further\s*delay',
        r'mandate.*(?:revoked|failed|rejected)',
        r'(?:txn|transaction).*(?:declined|failed)',
        r'(?:declined|failed).*insufficient',
        r'fund\s*bal|securities\s*bal',
        r'reported.*(?:fund|securities)',
        r'is\s+due\s+on',
        r'payable\s*by',
    ]
    for pat in non_txn_patterns:
        if re.search(pat, body_lower):
            return None
    
    if has_credit and not has_debit:
        return 'credit'
    elif has_debit and not has_credit:
        return 'debit'
    elif has_credit and has_debit:
        # First occurrence wins
        for i, ch in enumerate(body_lower):
            for kw in credit_kws:
                if body_lower[i:].startswith(kw):
                    return 'credit'
            for kw in debit_kws:
                if body_lower[i:].startswith(kw):
                    return 'debit'
    
    return None


def extract_transaction(sms: dict) -> Dict:
    """
    Extract ALL transaction details from a single SMS.
    
    Returns a rich transaction dict with:
    - amount, transaction_type, account, bank, counterparty,
      payment_method, reference, transaction_date, balance_after,
      description, raw_body
    """
    body = sms.get('body', '')
    sender = sms.get('address', '')
    timestamp = sms.get('date', '')
    
    amount = parse_amount(body)
    all_amounts = parse_all_amounts(body)
    txn_type = detect_transaction_type(body)
    account = parse_account(body)
    bank = parse_bank(sender, body)
    counterparty = parse_counterparty(body)
    payment_method = parse_payment_method(body)
    reference = parse_reference(body)
    txn_date = parse_transaction_date(body, timestamp)
    balance = parse_balance(body)
    
    # Build description from available info
    desc_parts = []
    if txn_type:
        desc_parts.append(txn_type.capitalize())
    if amount:
        desc_parts.append(f"Rs.{amount}")
    if counterparty:
        desc_parts.append(f"{'to' if txn_type == 'debit' else 'from'} {counterparty}")
    if payment_method:
        desc_parts.append(f"via {payment_method}")
    
    description = ' '.join(desc_parts) if desc_parts else body[:100]
    
    return {
        'sms_id': sms.get('_id', ''),
        'sender': sender,
        'amount': amount,
        'all_amounts': all_amounts,
        'transaction_type': txn_type,
        'account_number': account,
        'bank_name': bank,
        'counterparty': counterparty,
        'payment_method': payment_method,
        'reference_number': reference,
        'transaction_date': txn_date,
        'balance_after': balance,
        'description': description,
        'raw_body': body,
        'timestamp': timestamp,
    }


def extract_transactions_batch(sms_list: list) -> list:
    """Extract transaction details from a batch of SMS."""
    return [extract_transaction(sms) for sms in sms_list]
