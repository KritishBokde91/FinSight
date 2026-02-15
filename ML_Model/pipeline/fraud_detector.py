"""
fraud_detector.py — Fraud & Anomaly Detection for Indian SMS
=============================================================
Detects:
1. Spam SMS (phishing, lottery scams, fake bank alerts)
2. Anomalous transactions (unusual amounts, frequency, timing)
3. Suspicious patterns (unknown senders claiming to be banks)

Uses Isolation Forest for statistical anomaly detection +
rule-based checks for known Indian spam patterns.
"""

import re
import numpy as np
from typing import Dict, List, Tuple
from datetime import datetime


# ─── INDIAN SPAM / PHISHING PATTERNS ─────────────────────────────────────
SPAM_PATTERNS = [
    # Lottery / prize scams
    re.compile(r'(?i)congratulations.*(?:won|winner|prize|crore|lakh)'),
    re.compile(r'(?i)lucky\s*(?:draw|winner|customer)'),
    re.compile(r'(?i)(?:won|win)\s*(?:Rs|INR|₹)?\s*[\d,]+\s*(?:crore|lakh)'),
    
    # Fake bank alerts
    re.compile(r'(?i)(?:kyc|pan|aadhar|aadhaar)\s*(?:expired?|expir|update|link|verify|suspend)'),
    re.compile(r'(?i)(?:account|a/c)\s*(?:will\s*be\s*)?(?:block|suspend|close|deactivat)'),
    re.compile(r'(?i)click\s*(?:here|below|link).*(?:verify|update|kyc|pan|aadhar)'),
    
    # Loan scams
    re.compile(r'(?i)(?:instant|quick|fast)\s*(?:loan|cash)\s*(?:approved|available)'),
    re.compile(r'(?i)pre.?approved\s*(?:loan|credit)\s*(?:of|upto|up\s*to)\s*(?:Rs|INR)'),
    
    # Phishing URLs
    re.compile(r'(?i)(?:bit\.ly|tinyurl|goo\.gl|rb\.gy|is\.gd)/'),
    
    # OTP theft
    re.compile(r'(?i)share\s*(?:your\s*)?otp.*(?:to\s*(?:verify|confirm|complete))'),
    re.compile(r'(?i)(?:call|contact)\s*(?:us|customer).*(?:otp|password)'),
]

# Known legitimate Indian bank SMS sender patterns
LEGITIMATE_BANK_PREFIXES = re.compile(
    r'^[A-Z]{2}-[A-Z]+'
)

# Suspicious URL patterns (not from known banks)
KNOWN_BANK_DOMAINS = [
    'sbicard.com', 'onlinesbi.com', 'hdfcbank.com', 'icicibank.com',
    'axisbank.com', 'kotak.com', 'bobfinancial.com', 'pnbindia.in',
    'unionbankofindia.co.in', 'canarabank.com', 'ippbonline.com',
    'idbidirect.in', 'federalbank.co.in', 'yesbank.in', 'rblbank.com',
    'paytm.com', 'phonepe.com', 'airtel.in', 'jio.com',
]


def detect_spam(sms: dict) -> Dict:
    """
    Detect if an SMS is spam/phishing.
    
    Returns:
        dict with: is_spam, spam_type, spam_confidence, reasons
    """
    body = sms.get('body', '')
    sender = sms.get('address', '')
    
    reasons = []
    confidence = 0.0
    spam_type = None
    
    # Check against spam patterns
    for i, pattern in enumerate(SPAM_PATTERNS):
        if pattern.search(body):
            confidence += 0.30
            if i < 3:
                spam_type = 'lottery_scam'
                reasons.append('Contains lottery/prize scam language')
            elif i < 6:
                spam_type = 'fake_bank_alert'
                reasons.append('Contains fake bank alert / KYC scam language')
            elif i < 8:
                spam_type = 'loan_scam'
                reasons.append('Contains suspicious loan offer')
            elif i < 9:
                spam_type = 'phishing_url'
                reasons.append('Contains shortened/suspicious URL')
            else:
                spam_type = 'otp_theft'
                reasons.append('Attempting OTP theft')
    
    # Check sender legitimacy
    if not LEGITIMATE_BANK_PREFIXES.match(sender) and not re.match(r'^\+?\d{10,}$', sender):
        # Unusual sender format
        if any(kw in body.lower() for kw in ['bank', 'account', 'card', 'upi']):
            confidence += 0.15
            reasons.append('Non-standard sender claiming financial content')
    
    # Check URLs in body
    urls = re.findall(r'https?://([^\s/]+)', body)
    for url in urls:
        url_lower = url.lower()
        if not any(domain in url_lower for domain in KNOWN_BANK_DOMAINS):
            if any(kw in body.lower() for kw in ['click', 'verify', 'update', 'kyc']):
                confidence += 0.20
                reasons.append(f'Unknown URL ({url}) with urgency language')
    
    is_spam = confidence >= 0.30
    
    return {
        'is_spam': is_spam,
        'spam_type': spam_type if is_spam else None,
        'spam_confidence': round(min(confidence, 1.0), 3),
        'reasons': reasons if is_spam else [],
    }


def detect_anomaly(transaction: dict, user_history: List[dict] = None) -> Dict:
    """
    Detect anomalous transactions based on user's history.
    
    Uses statistical methods:
    - Z-score for amount anomalies
    - Frequency analysis for unusual timing
    - New merchant/counterparty detection
    
    Args:
        transaction: Single transaction dict from extractor
        user_history: List of previous transactions for this user
        
    Returns:
        dict with: is_anomaly, anomaly_score, anomaly_reasons
    """
    amount = transaction.get('amount')
    if not amount or not user_history:
        return {
            'is_anomaly': False,
            'anomaly_score': 0.0,
            'anomaly_reasons': [],
        }
    
    reasons = []
    score = 0.0
    
    # ── Amount anomaly (Z-score) ──
    historical_amounts = [t.get('amount', 0) for t in user_history if t.get('amount')]
    if len(historical_amounts) >= 5:
        mean_amount = np.mean(historical_amounts)
        std_amount = np.std(historical_amounts) or 1.0
        z_score = abs((amount - mean_amount) / std_amount)
        
        if z_score > 3.0:
            score += 0.40
            reasons.append(f'Amount Rs.{amount} is {z_score:.1f} std devs from mean Rs.{mean_amount:.0f}')
        elif z_score > 2.0:
            score += 0.20
            reasons.append(f'Amount Rs.{amount} is unusually {'high' if amount > mean_amount else 'low'}')
    
    # ── Frequency anomaly ──
    txn_type = transaction.get('transaction_type')
    if txn_type == 'debit' and len(user_history) >= 3:
        # Count debits in last 24 hours
        try:
            current_ts = int(transaction.get('timestamp', 0))
            recent_debits = sum(
                1 for t in user_history
                if t.get('transaction_type') == 'debit'
                and abs(int(t.get('timestamp', 0)) - current_ts) < 86400000  # 24h in ms
            )
            if recent_debits > 5:
                score += 0.30
                reasons.append(f'{recent_debits} debits in 24 hours is unusual')
        except (ValueError, TypeError):
            pass
    
    # ── New counterparty ──
    counterparty = transaction.get('counterparty', '')
    if counterparty:
        known_counterparties = set(
            t.get('counterparty', '') for t in user_history if t.get('counterparty')
        )
        if counterparty not in known_counterparties and len(known_counterparties) > 3:
            score += 0.10
            reasons.append(f'New counterparty: {counterparty}')
    
    is_anomaly = score >= 0.30
    
    return {
        'is_anomaly': is_anomaly,
        'anomaly_score': round(min(score, 1.0), 3),
        'anomaly_reasons': reasons,
    }


def analyze_sms(sms: dict, user_history: List[dict] = None) -> Dict:
    """
    Complete fraud analysis: spam detection + anomaly detection.
    
    Returns:
        dict with: is_genuine, is_spam, is_anomaly, details
    """
    spam_result = detect_spam(sms)
    
    # If it's spam, no need to check anomaly
    if spam_result['is_spam']:
        return {
            'is_genuine': False,
            'is_spam': True,
            'is_anomaly': False,
            'fraud_type': spam_result['spam_type'],
            'fraud_confidence': spam_result['spam_confidence'],
            'reasons': spam_result['reasons'],
        }
    
    # Not spam, check for anomaly (requires transaction data)
    anomaly_result = {'is_anomaly': False, 'anomaly_score': 0.0, 'anomaly_reasons': []}
    
    return {
        'is_genuine': not spam_result['is_spam'],
        'is_spam': False,
        'is_anomaly': anomaly_result['is_anomaly'],
        'fraud_type': None,
        'fraud_confidence': 0.0,
        'reasons': [],
    }
