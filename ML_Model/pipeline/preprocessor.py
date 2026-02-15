"""
preprocessor.py — SMS Data Preprocessor
========================================
Loads raw SMS data, cleans it, generates features, and exports CSV.
Works with ANY Indian SMS - no dependency on specific training data.
"""

import re
import json
import os
import pandas as pd
from typing import List, Dict
from pipeline.labeler import label_sms_batch, AMOUNT_PATTERN, ACCOUNT_PATTERN, \
    UPI_PATTERN, NEFT_PATTERN, IMPS_PATTERN, RTGS_PATTERN, CARD_PATTERN, \
    WALLET_PATTERN, BANK_SENDER_PATTERNS, CREDIT_INDICATORS, DEBIT_INDICATORS, \
    OTP_PATTERN, BALANCE_PATTERN


def clean_text(text: str) -> str:
    """Clean SMS text for processing."""
    if not text:
        return ""
    # Remove URLs
    text = re.sub(r'https?://\S+', '', text)
    # Remove extra whitespace
    text = re.sub(r'\s+', ' ', text).strip()
    return text


def extract_features(body: str, sender: str = "") -> Dict:
    """
    Extract hand-crafted features from SMS text.
    These are universal features that work for ANY Indian bank SMS.
    """
    body_clean = clean_text(body)
    body_lower = body_clean.lower()
    sender_upper = sender.upper()
    
    return {
        # ── Text features ──
        'body_length': len(body_clean),
        'word_count': len(body_clean.split()),
        'has_url': bool(re.search(r'https?://', body)),
        'has_phone_number': bool(re.search(r'\b\d{10}\b', body)),
        
        # ── Financial features ──
        'has_amount': bool(AMOUNT_PATTERN.search(body)),
        'has_account': bool(ACCOUNT_PATTERN.search(body)),
        'has_credit_word': bool(CREDIT_INDICATORS.search(body)),
        'has_debit_word': bool(DEBIT_INDICATORS.search(body)),
        'has_balance': bool(BALANCE_PATTERN.search(body)),
        
        # ── Payment method features ──
        'has_upi': bool(UPI_PATTERN.search(body)),
        'has_neft': bool(NEFT_PATTERN.search(body)),
        'has_imps': bool(IMPS_PATTERN.search(body)),
        'has_rtgs': bool(RTGS_PATTERN.search(body)),
        'has_card': bool(CARD_PATTERN.search(body)),
        'has_wallet': bool(WALLET_PATTERN.search(body)),
        
        # ── Sender features ──
        'is_bank_sender': bool(BANK_SENDER_PATTERNS.search(sender_upper)),
        'is_shortcode_sender': bool(re.match(r'^[A-Z]{2}-', sender_upper)),
        'is_phone_sender': bool(re.match(r'^\+?\d{10,}$', sender)),
        
        # ── OTP / Security features ──
        'has_otp': bool(OTP_PATTERN.search(body)),
        
        # ── Keyword counts ──
        'financial_keyword_count': sum(1 for kw in 
            ['rs', 'inr', 'credited', 'debited', 'a/c', 'account', 'balance',
             'transaction', 'transfer', 'payment', 'upi', 'neft', 'imps',
             'card', 'emi', 'loan', 'bank']
            if kw in body_lower),
    }


def load_and_preprocess(json_path: str) -> pd.DataFrame:
    """
    Load SMS data from JSON and create a fully featured DataFrame.
    
    Returns DataFrame with original data + labels + features.
    """
    with open(json_path, 'r', encoding='utf-8') as f:
        raw_data = json.load(f)
    
    # Auto-label
    labeled_data = label_sms_batch(raw_data)
    
    # Build DataFrame
    records = []
    for sms in labeled_data:
        body = sms.get('body', '')
        sender = sms.get('address', '')
        
        record = {
            'sms_id': sms.get('_id', ''),
            'thread_id': sms.get('thread_id', ''),
            'sender': sender,
            'body': body,
            'body_clean': clean_text(body),
            'timestamp': sms.get('date', ''),
            'date_sent': sms.get('date_sent', ''),
            'sms_type': sms.get('type', ''),
            'read': sms.get('read', ''),
            'service_center': sms.get('service_center', ''),
            'label': sms.get('label', ''),
            'sub_label': sms.get('sub_label', ''),
            'label_confidence': sms.get('label_confidence', 0),
        }
        
        # Add computed features
        features = extract_features(body, sender)
        record.update(features)
        
        records.append(record)
    
    df = pd.DataFrame(records)
    return df


def export_csv(df: pd.DataFrame, output_path: str):
    """Export DataFrame to CSV for training / inspection."""
    os.makedirs(os.path.dirname(output_path) or '.', exist_ok=True)
    df.to_csv(output_path, index=False, encoding='utf-8')
    print(f"[Preprocessor] Exported {len(df)} SMS to {output_path}")
    
    # Print summary
    print("\n── Label Distribution ──")
    for label, count in df['label'].value_counts().items():
        pct = count / len(df) * 100
        print(f"  {label:30s} {count:5d}  ({pct:.1f}%)")
    
    print("\n── Sub-Label Distribution ──")
    for sub, count in df['sub_label'].value_counts().items():
        pct = count / len(df) * 100
        print(f"  {sub:30s} {count:5d}  ({pct:.1f}%)")


def preprocess_single_sms(sms: dict) -> dict:
    """
    Preprocess a single SMS message — used in real-time API processing.
    Returns the SMS enriched with label and features.
    """
    from pipeline.labeler import label_sms
    
    body = sms.get('body', '')
    sender = sms.get('address', '')
    
    label, sub_label, confidence = label_sms(body, sender)
    features = extract_features(body, sender)
    
    result = dict(sms)
    result['label'] = label
    result['sub_label'] = sub_label
    result['label_confidence'] = round(confidence, 3)
    result['body_clean'] = clean_text(body)
    result.update(features)
    
    return result
