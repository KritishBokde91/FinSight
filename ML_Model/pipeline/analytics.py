"""
analytics.py — Financial Analytics Engine
==========================================
Computes weekly, monthly, quarterly, and yearly analytics
from processed transaction data.
"""

from datetime import datetime, timedelta
from typing import Dict, List, Optional
from collections import defaultdict


def _ts_to_datetime(ts_str: str) -> Optional[datetime]:
    """Convert millisecond timestamp string to datetime."""
    try:
        return datetime.fromtimestamp(int(ts_str) / 1000)
    except (ValueError, TypeError, OSError):
        return None


def compute_analytics(transactions: List[dict], period: str = 'monthly') -> Dict:
    """
    Compute analytics from processed transactions.
    
    Args:
        transactions: List of transaction dicts from extractor
        period: 'weekly', 'monthly', 'quarterly', 'yearly'
    
    Returns:
        dict with: summary, period_breakdown, category_breakdown, top_merchants
    """
    if not transactions:
        return {
            'summary': _empty_summary(),
            'period_breakdown': [],
            'category_breakdown': {},
            'top_merchants': [],
        }
    
    # Separate credits and debits
    credits = [t for t in transactions if t.get('transaction_type') == 'credit' and t.get('amount')]
    debits = [t for t in transactions if t.get('transaction_type') == 'debit' and t.get('amount')]
    
    total_credit = sum(t['amount'] for t in credits)
    total_debit = sum(t['amount'] for t in debits)
    
    summary = {
        'total_transactions': len(transactions),
        'total_credits': len(credits),
        'total_debits': len(debits),
        'total_credit_amount': round(total_credit, 2),
        'total_debit_amount': round(total_debit, 2),
        'net_flow': round(total_credit - total_debit, 2),
        'avg_credit': round(total_credit / len(credits), 2) if credits else 0,
        'avg_debit': round(total_debit / len(debits), 2) if debits else 0,
        'largest_credit': round(max((t['amount'] for t in credits), default=0), 2),
        'largest_debit': round(max((t['amount'] for t in debits), default=0), 2),
    }
    
    # Period breakdown
    period_breakdown = _compute_period_breakdown(transactions, period)
    
    # Payment method breakdown
    method_breakdown = _compute_method_breakdown(transactions)
    
    # Bank breakdown
    bank_breakdown = _compute_bank_breakdown(transactions)
    
    # Top merchants/counterparties
    top_merchants = _compute_top_merchants(debits, limit=10)
    
    return {
        'summary': summary,
        'period_breakdown': period_breakdown,
        'payment_methods': method_breakdown,
        'bank_breakdown': bank_breakdown,
        'top_merchants': top_merchants,
    }


def _empty_summary() -> Dict:
    return {
        'total_transactions': 0,
        'total_credits': 0,
        'total_debits': 0,
        'total_credit_amount': 0,
        'total_debit_amount': 0,
        'net_flow': 0,
        'avg_credit': 0,
        'avg_debit': 0,
        'largest_credit': 0,
        'largest_debit': 0,
    }


def _get_period_key(dt: datetime, period: str) -> str:
    """Get the period key for grouping."""
    if period == 'weekly':
        # ISO week
        iso = dt.isocalendar()
        return f"{iso[0]}-W{iso[1]:02d}"
    elif period == 'monthly':
        return dt.strftime('%Y-%m')
    elif period == 'quarterly':
        quarter = (dt.month - 1) // 3 + 1
        return f"{dt.year}-Q{quarter}"
    elif period == 'yearly':
        return str(dt.year)
    return dt.strftime('%Y-%m')


def _compute_period_breakdown(transactions: List[dict], period: str) -> List[dict]:
    """Group transactions by time period."""
    groups = defaultdict(lambda: {'credit': 0, 'debit': 0, 'credit_count': 0, 'debit_count': 0})
    
    for txn in transactions:
        dt = _ts_to_datetime(txn.get('timestamp', ''))
        if not dt:
            continue
        
        key = _get_period_key(dt, period)
        amount = txn.get('amount', 0) or 0
        txn_type = txn.get('transaction_type', '')
        
        if txn_type == 'credit':
            groups[key]['credit'] += amount
            groups[key]['credit_count'] += 1
        elif txn_type == 'debit':
            groups[key]['debit'] += amount
            groups[key]['debit_count'] += 1
    
    result = []
    for key in sorted(groups.keys()):
        g = groups[key]
        result.append({
            'period': key,
            'credit_amount': round(g['credit'], 2),
            'debit_amount': round(g['debit'], 2),
            'net_flow': round(g['credit'] - g['debit'], 2),
            'credit_count': g['credit_count'],
            'debit_count': g['debit_count'],
            'total_count': g['credit_count'] + g['debit_count'],
        })
    
    return result


def _compute_method_breakdown(transactions: List[dict]) -> Dict:
    """Breakdown by payment method."""
    methods = defaultdict(lambda: {'count': 0, 'amount': 0})
    
    for txn in transactions:
        method = txn.get('payment_method', 'Unknown') or 'Unknown'
        amount = txn.get('amount', 0) or 0
        methods[method]['count'] += 1
        methods[method]['amount'] += amount
    
    return {
        k: {'count': v['count'], 'amount': round(v['amount'], 2)}
        for k, v in sorted(methods.items(), key=lambda x: x[1]['amount'], reverse=True)
    }


def _compute_bank_breakdown(transactions: List[dict]) -> Dict:
    """Breakdown by bank."""
    banks = defaultdict(lambda: {'count': 0, 'credit': 0, 'debit': 0})
    
    for txn in transactions:
        bank = txn.get('bank_name', 'Unknown') or 'Unknown'
        amount = txn.get('amount', 0) or 0
        banks[bank]['count'] += 1
        
        if txn.get('transaction_type') == 'credit':
            banks[bank]['credit'] += amount
        else:
            banks[bank]['debit'] += amount
    
    return {
        k: {
            'count': v['count'],
            'credit': round(v['credit'], 2),
            'debit': round(v['debit'], 2),
        }
        for k, v in sorted(banks.items(), key=lambda x: x[1]['count'], reverse=True)
    }


def _compute_top_merchants(debits: List[dict], limit: int = 10) -> List[dict]:
    """Top merchants/counterparties by spending."""
    merchants = defaultdict(lambda: {'count': 0, 'total': 0})
    
    for txn in debits:
        merchant = txn.get('counterparty', 'Unknown') or 'Unknown'
        amount = txn.get('amount', 0) or 0
        merchants[merchant]['count'] += 1
        merchants[merchant]['total'] += amount
    
    sorted_merchants = sorted(
        merchants.items(), key=lambda x: x[1]['total'], reverse=True
    )[:limit]
    
    return [
        {'name': name, 'count': data['count'], 'total_amount': round(data['total'], 2)}
        for name, data in sorted_merchants
    ]
