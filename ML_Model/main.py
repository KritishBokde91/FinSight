"""
main.py — FinSight Backend API
================================
Serves SMS processing, transaction extraction, analytics, AI insights,
auto-retraining triggers, and web-crawled data.
"""

import os
import sys
import json
import hashlib
from datetime import datetime
from typing import Optional, List, Any

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

# Add project root to path for pipeline imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pipeline.labeler import label_sms
from pipeline.preprocessor import preprocess_single_sms, clean_text
from pipeline.extractor import extract_transaction
from pipeline.fraud_detector import detect_spam, detect_anomaly, analyze_sms
from pipeline.analytics import compute_analytics
from auto_trainer import trainer as auto_trainer

# Lazy imports for optional deps
try:
    from ollama_model import OllamaModel
    llm = OllamaModel(model_name="vicuna:13b")
except Exception as e:
    print(f"[LLM] Ollama not available: {e}")
    llm = None

try:
    from web_crawler import crawler as web_crawler, should_crawl_web
    HAS_CRAWLER = True
except ImportError:
    HAS_CRAWLER = False
    print("[WebCrawler] Not available — install trafilatura + duckduckgo-search")

try:
    import supabase_client as supa
    HAS_SUPABASE = True
except Exception as e:
    HAS_SUPABASE = False
    print(f"[Supabase] Not available: {e}")

app = FastAPI(title="FinSight API", version="3.0")

# ─── Storage (file-based fallback) ──────────────────────────────────────
DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
os.makedirs(DATA_DIR, exist_ok=True)

SMS_RAW_FILE = os.path.join(os.path.dirname(__file__), "sms_data.json")
TRANSACTIONS_FILE = os.path.join(DATA_DIR, "transactions.json")
PROCESSED_FILE = os.path.join(DATA_DIR, "processed_sms.json")
USERS_FILE = os.path.join(DATA_DIR, "users.json")


def _load_json(path: str) -> list:
    if os.path.exists(path):
        with open(path, "r") as f:
            return json.load(f)
    return []


def _safe_float(val) -> float:
    """Safely convert any value to float, defaulting to 0.0."""
    if val is None:
        return 0.0
    try:
        return float(val)
    except (ValueError, TypeError):
        return 0.0


def _save_json(path: str, data: list):
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def _transaction_hash(txn: dict) -> str:
    """Content-based dedup key: SHA-256 of amount|date|type|sender|bank."""
    parts = [
        str(_safe_float(txn.get('amount', 0))),
        str(txn.get('transaction_date', '')),
        str(txn.get('transaction_type', '')),
        str(txn.get('sender', '')),
        str(txn.get('bank_name', '')),
        str(txn.get('counterparty', '')),
    ]
    key = '|'.join(parts)
    return hashlib.sha256(key.encode()).hexdigest()


def _deduplicate_transactions(transactions: list) -> list:
    """Remove duplicate transactions by content hash. Keeps first occurrence."""
    seen_hashes = set()
    unique = []
    for txn in transactions:
        h = _transaction_hash(txn)
        if h not in seen_hashes:
            seen_hashes.add(h)
            unique.append(txn)
    return unique


# ─── Pydantic Models ───────────────────────────────────────────────────
class SmsPayload(BaseModel):
    data: List[Any]
    user_id: Optional[str] = None  # For Supabase user tracking


class PromptRequest(BaseModel):
    prompt: str
    system_prompt: Optional[str] = None
    user_id: Optional[str] = None


class CategoryUpdate(BaseModel):
    category: str
    user_id: Optional[str] = None


class SignupRequest(BaseModel):
    email: str
    password: str
    display_name: Optional[str] = None


class LoginRequest(BaseModel):
    email: str
    password: str


# Payload for UPI notification data
class NotificationPayload(BaseModel):
    data: List[Any]
    user_id: Optional[str] = None


# ═══════════════════════════════════════════════════════════════════════
# STARTUP
# ═══════════════════════════════════════════════════════════════════════

@app.on_event("startup")
async def startup_event():
    print("\n" + "="*60)
    print("   🚀 FinSight API v3.0 — Starting Up")
    print("="*60)
    auto_trainer.start_background()
    
    # Deduplicate existing transactions on startup
    txns = _load_json(TRANSACTIONS_FILE)
    if txns:
        deduped = _deduplicate_transactions(txns)
        if len(deduped) < len(txns):
            _save_json(TRANSACTIONS_FILE, deduped)
            print(f"[Startup] Cleaned {len(txns) - len(deduped)} duplicate transactions")
            print(f"[Startup] {len(deduped)} unique transactions remain")
        else:
            print(f"[Startup] {len(txns)} transactions — no duplicates found")
    
    # Also dedup raw SMS
    raw = _load_json(SMS_RAW_FILE)
    if raw:
        seen_ids = set()
        unique_raw = []
        for s in raw:
            sid = str(s.get('_id', ''))
            if sid and sid not in seen_ids:
                seen_ids.add(sid)
                unique_raw.append(s)
            elif not sid:
                unique_raw.append(s)
        if len(unique_raw) < len(raw):
            _save_json(SMS_RAW_FILE, unique_raw)
            print(f"[Startup] Cleaned {len(raw) - len(unique_raw)} duplicate raw SMS")
    
    print(f"[Storage] SMS file: {SMS_RAW_FILE}")
    print(f"[Storage] Transactions file: {TRANSACTIONS_FILE}")
    print(f"[Supabase] Available: {HAS_SUPABASE}")
    print(f"[LLM] Available: {llm is not None}")
    print(f"[WebCrawler] Available: {HAS_CRAWLER}")
    print()


# ═══════════════════════════════════════════════════════════════════════
# AUTH ENDPOINTS (GoTrue + file fallback)
# ═══════════════════════════════════════════════════════════════════════

def _hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()


@app.post("/api/auth/signup")
async def signup(request: SignupRequest):
    """Register a new user via GoTrue Auth (email) + file fallback."""
    # Try Supabase GoTrue first
    if HAS_SUPABASE:
        try:
            supa_user = supa.auth_signup(
                email=request.email,
                password=request.password,
                display_name=request.display_name or request.email.split('@')[0],
            )
            if supa_user and supa_user.get('id'):
                # Also save to file for offline fallback
                users = _load_json(USERS_FILE)
                file_user = {
                    "id": supa_user['id'],
                    "email": request.email,
                    "display_name": request.display_name or request.email.split('@')[0],
                    "password_hash": _hash_password(request.password),
                    "created_at": datetime.now().isoformat(),
                }
                users = [u for u in users if u.get('email') != request.email]
                users.append(file_user)
                _save_json(USERS_FILE, users)
                
                safe_user = {k: v for k, v in file_user.items() if k != "password_hash"}
                return {"status": "ok", "user": safe_user}
            else:
                raise HTTPException(status_code=500, detail="Supabase signup failed")
        except HTTPException:
            raise
        except Exception as e:
            print(f"[Auth] Supabase signup error, falling back to file: {e}")
    
    # File-based fallback
    users = _load_json(USERS_FILE)
    for u in users:
        if u.get("email") == request.email:
            raise HTTPException(status_code=409, detail="Email already registered")
    
    import uuid
    user = {
        "id": str(uuid.uuid4()),
        "email": request.email,
        "display_name": request.display_name or request.email.split('@')[0],
        "password_hash": _hash_password(request.password),
        "created_at": datetime.now().isoformat(),
    }
    users.append(user)
    _save_json(USERS_FILE, users)
    
    safe_user = {k: v for k, v in user.items() if k != "password_hash"}
    return {"status": "ok", "user": safe_user}


@app.post("/api/auth/login")
async def login(request: LoginRequest):
    """Authenticate via GoTrue Auth (email) + file fallback."""
    # Try Supabase GoTrue first
    if HAS_SUPABASE:
        try:
            supa_user = supa.auth_login(
                email=request.email,
                password=request.password,
            )
            if supa_user and supa_user.get('id'):
                return {"status": "ok", "user": supa_user}
        except Exception as e:
            print(f"[Auth] Supabase login error, falling back to file: {e}")
    
    # File-based fallback
    users = _load_json(USERS_FILE)
    for u in users:
        if u.get("email") == request.email:
            if u.get("password_hash") == _hash_password(request.password):
                safe_user = {k: v for k, v in u.items() if k != "password_hash"}
                return {"status": "ok", "user": safe_user}
            else:
                raise HTTPException(status_code=401, detail="Invalid password")
    
    raise HTTPException(status_code=404, detail="User not found")


@app.get("/api/auth/user/{user_id}")
async def get_user(user_id: str):
    """Get user profile from Supabase or file."""
    if HAS_SUPABASE:
        try:
            supa_user = supa.get_user_by_id(user_id)
            if supa_user:
                return {"user": supa_user}
        except Exception as e:
            print(f"[Auth] Supabase get user error: {e}")
    
    users = _load_json(USERS_FILE)
    for u in users:
        if u.get("id") == user_id:
            safe_user = {k: v for k, v in u.items() if k != "password_hash"}
            return {"user": safe_user}
    raise HTTPException(status_code=404, detail="User not found")


# ═══════════════════════════════════════════════════════════════════════
# SMS ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════

@app.post("/api/sms")
async def receive_sms(payload: SmsPayload):
    """
    Receive SMS from Flutter app, process through ML pipeline.
    Content-hash deduplication ensures no duplicate transactions.
    """
    try:
        sms_list = payload.data
        if not sms_list:
            return {"status": "ok", "message": "No SMS to process", "count": 0}
        
        user_id = payload.user_id

        # Step 1: Dedup raw SMS by _id
        existing_raw = _load_json(SMS_RAW_FILE)
        existing_ids = {str(s.get('_id', '')) for s in existing_raw if s.get('_id')}
        new_raw = [s for s in sms_list if str(s.get('_id', '')) not in existing_ids]
        
        if not new_raw:
            return {
                "status": "ok",
                "message": "All SMS already processed",
                "count": len(sms_list),
                "new_sms": 0,
                "transactions_found": 0,
            }
        
        existing_raw.extend(new_raw)
        _save_json(SMS_RAW_FILE, existing_raw)

        # Step 2: Store to Supabase with dedup (if available)
        new_sms_count = 0
        if HAS_SUPABASE and user_id:
            new_sms_count = supa.store_sms_batch(user_id, new_raw)
            print(f"[Supabase] {new_sms_count} new SMS stored (deduped)")

        # Step 3: Process ONLY new SMS through pipeline
        processed = []
        transactions = []
        spam_count = 0

        existing_transactions = _load_json(TRANSACTIONS_FILE)
        existing_hashes = {_transaction_hash(t) for t in existing_transactions}

        for sms in new_raw:
            enriched = preprocess_single_sms(sms)
            fraud_result = analyze_sms(sms)
            enriched['is_spam'] = fraud_result['is_spam']
            enriched['is_genuine'] = fraud_result['is_genuine']
            enriched['fraud_type'] = fraud_result.get('fraud_type')
            
            if fraud_result['is_spam']:
                spam_count += 1
            
            processed.append(enriched)
            
            if enriched.get('label') == 'financial_transaction' and enriched.get('is_genuine', True):
                txn = extract_transaction(sms)
                
                if txn.get('transaction_type') is None:
                    continue
                    
                txn['label'] = enriched['label']
                txn['sub_label'] = enriched['sub_label']
                txn['label_confidence'] = enriched['label_confidence']
                
                anomaly = detect_anomaly(txn, existing_transactions)
                txn['is_anomaly'] = anomaly['is_anomaly']
                txn['anomaly_score'] = anomaly['anomaly_score']
                
                # Content-hash dedup: skip if identical transaction exists
                txn_hash = _transaction_hash(txn)
                if txn_hash in existing_hashes:
                    continue
                
                existing_hashes.add(txn_hash)
                transactions.append(txn)
                
                # Store to Supabase
                if HAS_SUPABASE and user_id:
                    supa.store_transaction(user_id, txn)

        # Step 4: Save to file
        existing_processed = _load_json(PROCESSED_FILE)
        existing_processed.extend(processed)
        _save_json(PROCESSED_FILE, existing_processed)

        existing_transactions.extend(transactions)
        _save_json(TRANSACTIONS_FILE, existing_transactions)

        # Check auto-retrain
        retrain_status = auto_trainer.get_status()
        if auto_trainer.should_retrain():
            print("[AutoTrainer] Threshold met! Starting retrain...")
            auto_trainer.retrain(triggered_by='threshold')

        print(f"[SMS API] Received {len(sms_list)} SMS ({len(new_raw)} new) | "
              f"{len(transactions)} transactions | {spam_count} spam | "
              f"Retrain progress: {retrain_status['progress_to_retrain']}%")

        return {
            "status": "ok",
            "message": f"Processed {len(new_raw)} new SMS",
            "count": len(sms_list),
            "new_sms": len(new_raw),
            "transactions_found": len(transactions),
            "spam_detected": spam_count,
            "total_raw": len(existing_raw),
            "total_transactions": len(existing_transactions),
            "retrain_progress": retrain_status['progress_to_retrain'],
        }
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/sms")
async def get_all_sms():
    """Retrieve all stored raw SMS."""
    data = _load_json(SMS_RAW_FILE)
    return {"data": data, "count": len(data)}


@app.delete("/api/sms")
async def clear_sms():
    """Clear all stored SMS and processed data."""
    _save_json(SMS_RAW_FILE, [])
    _save_json(PROCESSED_FILE, [])
    _save_json(TRANSACTIONS_FILE, [])
    return {"status": "ok", "message": "All data cleared"}


# ═══════════════════════════════════════════════════════════════════════
# TRANSACTION ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════

@app.get("/api/transactions")
async def get_transactions(user_id: Optional[str] = None):
    """Get all extracted transactions, optionally filtered by user."""
    if HAS_SUPABASE and user_id:
        data = supa.get_user_transactions(user_id)
        return {"data": data, "count": len(data)}
    
    data = _load_json(TRANSACTIONS_FILE)
    return {"data": data, "count": len(data)}


@app.patch("/api/transactions/{txn_id}/category")
async def update_category(txn_id: int, update: CategoryUpdate):
    """Update a transaction's category (user-edited)."""
    if HAS_SUPABASE and update.user_id:
        result = supa.update_transaction_category(txn_id, update.category, update.user_id)
        if result:
            return {"status": "ok", "transaction": result}
        raise HTTPException(status_code=404, detail="Transaction not found")
    
    # File fallback
    transactions = _load_json(TRANSACTIONS_FILE)
    for txn in transactions:
        if str(txn.get('sms_id')) == str(txn_id):
            txn['category'] = update.category
            txn['category_edited'] = True
            _save_json(TRANSACTIONS_FILE, transactions)
            return {"status": "ok", "transaction": txn}
    
    raise HTTPException(status_code=404, detail="Transaction not found")


@app.get("/api/categories")
async def get_categories():
    """Get all available transaction categories."""
    if HAS_SUPABASE:
        return {"categories": supa.get_categories()}
    
    # Fallback
    default = [
        {"name": "shopping", "icon": "shopping_bag", "color": "#FF6B6B"},
        {"name": "food", "icon": "restaurant", "color": "#FFA726"},
        {"name": "travel", "icon": "flight", "color": "#42A5F5"},
        {"name": "bills", "icon": "receipt", "color": "#AB47BC"},
        {"name": "salary", "icon": "account_balance_wallet", "color": "#66BB6A"},
        {"name": "transfer", "icon": "swap_horiz", "color": "#26C6DA"},
        {"name": "entertainment", "icon": "movie", "color": "#EC407A"},
        {"name": "health", "icon": "local_hospital", "color": "#EF5350"},
        {"name": "education", "icon": "school", "color": "#5C6BC0"},
        {"name": "investment", "icon": "trending_up", "color": "#7CB342"},
        {"name": "emi", "icon": "credit_card", "color": "#FF7043"},
        {"name": "recharge", "icon": "phone_android", "color": "#78909C"},
        {"name": "other", "icon": "help_outline", "color": "#BDBDBD"},
    ]
    return {"categories": default}


@app.post("/api/sms/process")
async def reprocess_all_sms():
    """Re-process all stored raw SMS through the ML pipeline with dedup."""
    try:
        raw_sms = _load_json(SMS_RAW_FILE)
        if not raw_sms:
            return {"status": "ok", "message": "No SMS to process"}

        processed = []
        transactions = []
        spam_count = 0
        seen_hashes = set()

        for sms in raw_sms:
            enriched = preprocess_single_sms(sms)
            fraud_result = analyze_sms(sms)
            enriched['is_spam'] = fraud_result['is_spam']
            enriched['is_genuine'] = fraud_result['is_genuine']

            if fraud_result['is_spam']:
                spam_count += 1

            processed.append(enriched)

            if enriched.get('label') == 'financial_transaction' and enriched.get('is_genuine', True):
                txn = extract_transaction(sms)
                
                if txn.get('transaction_type') is None:
                    continue
                    
                txn['label'] = enriched['label']
                txn['sub_label'] = enriched['sub_label']
                txn['label_confidence'] = enriched['label_confidence']
                
                # Content-hash dedup
                txn_hash = _transaction_hash(txn)
                if txn_hash in seen_hashes:
                    continue
                seen_hashes.add(txn_hash)
                transactions.append(txn)

        _save_json(PROCESSED_FILE, processed)
        _save_json(TRANSACTIONS_FILE, transactions)

        return {
            "status": "ok",
            "total_processed": len(processed),
            "transactions_found": len(transactions),
            "spam_detected": spam_count,
        }
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


# ═══════════════════════════════════════════════════════════════════════
# UPI NOTIFICATION ENDPOINT
# ═══════════════════════════════════════════════════════════════════════

@app.post("/api/notifications")
async def receive_notifications(payload: NotificationPayload):
    """
    Receive UPI payment notifications from Android NotificationListenerService.
    Converts notifications into transactions with content-hash dedup.
    """
    try:
        notifications = payload.data
        if not notifications:
            return {"status": "ok", "message": "No notifications", "count": 0}
        
        user_id = payload.user_id
        existing_transactions = _load_json(TRANSACTIONS_FILE)
        existing_hashes = {_transaction_hash(t) for t in existing_transactions}
        
        new_transactions = []
        for notif in notifications:
            # Build transaction from notification data
            txn = {
                "sms_id": f"notif_{notif.get('timestamp', '')}_{notif.get('package', '')}",
                "sender": notif.get("app_name", notif.get("package", "UPI")),
                "amount": _safe_float(notif.get("amount")),
                "transaction_type": notif.get("transaction_type", "debit"),
                "payment_method": "UPI",
                "category": notif.get("category", "other"),
                "counterparty": notif.get("counterparty", ""),
                "description": notif.get("title", ""),
                "raw_body": notif.get("text", ""),
                "transaction_date": notif.get("timestamp", datetime.now().isoformat()),
                "bank_name": notif.get("app_name", ""),
                "label": "financial_transaction",
                "sub_label": "upi_notification",
                "label_confidence": 0.95,
                "is_anomaly": False,
                "anomaly_score": 0,
            }
            
            # Content-hash dedup
            txn_hash = _transaction_hash(txn)
            if txn_hash in existing_hashes:
                continue
            
            existing_hashes.add(txn_hash)
            new_transactions.append(txn)
            
            # Store to Supabase
            if HAS_SUPABASE and user_id:
                supa.store_transaction(user_id, txn)
        
        existing_transactions.extend(new_transactions)
        _save_json(TRANSACTIONS_FILE, existing_transactions)
        
        print(f"[Notifications] Received {len(notifications)} | "
              f"{len(new_transactions)} new transactions")
        
        return {
            "status": "ok",
            "received": len(notifications),
            "new_transactions": len(new_transactions),
            "total_transactions": len(existing_transactions),
        }
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


# ═══════════════════════════════════════════════════════════════════════
# ANALYTICS ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════

@app.get("/api/analytics")
async def get_analytics(
    period: str = Query(default="monthly", pattern="^(weekly|monthly|quarterly|yearly)$"),
    user_id: Optional[str] = None,
):
    """Get financial analytics."""
    if HAS_SUPABASE and user_id:
        transactions = supa.get_user_transactions(user_id, limit=5000)
    else:
        transactions = _load_json(TRANSACTIONS_FILE)
    
    analytics = compute_analytics(transactions, period)
    return analytics


@app.get("/api/analytics/summary")
async def get_analytics_summary(user_id: Optional[str] = None):
    """Get quick summary of all analytics periods."""
    if HAS_SUPABASE and user_id:
        transactions = supa.get_user_transactions(user_id, limit=5000)
    else:
        transactions = _load_json(TRANSACTIONS_FILE)
    
    return {
        "weekly": compute_analytics(transactions, "weekly"),
        "monthly": compute_analytics(transactions, "monthly"),
        "quarterly": compute_analytics(transactions, "quarterly"),
        "yearly": compute_analytics(transactions, "yearly"),
    }


# ═══════════════════════════════════════════════════════════════════════
# ML TRAINING ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════

@app.get("/api/ml/status")
async def ml_training_status():
    """Get current ML model training status."""
    return auto_trainer.get_status()


@app.post("/api/ml/retrain")
async def trigger_retrain():
    """Manually trigger ML model retraining."""
    result = auto_trainer.retrain(triggered_by="manual")
    return result


# ═══════════════════════════════════════════════════════════════════════
# AI INSIGHTS ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════

def _build_financial_context(user_id: Optional[str] = None) -> str:
    """Build financial context for AI system prompt."""
    if HAS_SUPABASE and user_id:
        transactions = supa.get_user_transactions(user_id, limit=100)
    else:
        transactions = _load_json(TRANSACTIONS_FILE)[-100:]
    
    if not transactions:
        return "No financial data available yet."
    
    # Summarize
    total_credit = sum(_safe_float(t.get('amount')) for t in transactions if t.get('transaction_type') == 'credit')
    total_debit = sum(_safe_float(t.get('amount')) for t in transactions if t.get('transaction_type') == 'debit')
    
    # Category breakdown
    categories = {}
    for t in transactions:
        cat = t.get('category', 'other')
        amt = _safe_float(t.get('amount'))
        if t.get('transaction_type') == 'debit':
            categories[cat] = categories.get(cat, 0) + amt
    
    # Payment methods
    methods = {}
    for t in transactions:
        method = t.get('payment_method', 'other')
        methods[method] = methods.get(method, 0) + 1
    
    # Top merchants
    merchants = {}
    for t in transactions:
        cp = t.get('counterparty') or t.get('receiver') or 'Unknown'
        merchants[cp] = merchants.get(cp, 0) + 1
    top_merchants = sorted(merchants.items(), key=lambda x: x[1], reverse=True)[:5]
    
    context = f"""
USER FINANCIAL SUMMARY (last {len(transactions)} transactions):
- Total Income: ₹{total_credit:,.2f}
- Total Expense: ₹{total_debit:,.2f}
- Net Flow: ₹{total_credit - total_debit:,.2f}

SPENDING BY CATEGORY:
{chr(10).join(f'  - {cat}: ₹{amt:,.2f}' for cat, amt in sorted(categories.items(), key=lambda x: x[1], reverse=True))}

PAYMENT METHODS:
{chr(10).join(f'  - {m}: {c} transactions' for m, c in sorted(methods.items(), key=lambda x: x[1], reverse=True)[:5])}

TOP MERCHANTS:
{chr(10).join(f'  - {m}: {c} transactions' for m, c in top_merchants)}
"""
    return context


@app.post("/api/ai/chat")
async def ai_chat(request: PromptRequest):
    """
    AI chat with financial context + optional web crawling.
    Uses Server-Sent Events (SSE) for real-time streaming:
      event: status  → searching/crawling progress
      event: sources → web source metadata
      event: token   → LLM response chunk
      event: done    → stream complete
    """
    if not llm:
        raise HTTPException(status_code=503, detail="LLM not available")
    
    user_query = request.prompt
    user_id = request.user_id
    
    async def generate_sse():
        web_results = []
        search_queries = []
        
        # Step 1: Web crawling (streamed with status events)
        if HAS_CRAWLER:
            search_queries = should_crawl_web(user_query, llm_model=None)
            
            if search_queries:
                yield f"event: status\ndata: {json.dumps({'phase': 'searching', 'message': 'Searching the web...'})}\n\n"
                
                for i, query in enumerate(search_queries[:3]):
                    yield f"event: status\ndata: {json.dumps({'phase': 'crawling', 'message': f'Crawling: {query}', 'progress': i+1, 'total': min(len(search_queries), 3)})}\n\n"
                    
                    results = web_crawler.search_and_extract(query)
                    web_results.extend(results)
                
                # Send sources metadata
                if web_results:
                    sources_meta = [
                        {"title": r['title'], "url": r['url'], "extracted": r.get('extracted', False)}
                        for r in web_results[:5]
                    ]
                    yield f"event: sources\ndata: {json.dumps(sources_meta)}\n\n"
                
                yield f"event: status\ndata: {json.dumps({'phase': 'analyzing', 'message': 'Analyzing results...'})}\n\n"
        
        # Step 2: Build context
        financial_context = _build_financial_context(user_id)
        
        web_context = ""
        if web_results:
            web_context = "\n\nWEB SEARCH RESULTS:\n"
            for i, r in enumerate(web_results[:5], 1):
                web_context += f"\n[{i}] {r['title']}\nURL: {r['url']}\n{r.get('content', r.get('snippet', ''))[:500]}\n"
        
        system_prompt = (
            request.system_prompt or
            "You are FinSight AI, a premium Indian financial advisor. "
            "You have access to the user's transaction data and provide personalized advice. "
            "Be concise, specific, and actionable. Use ₹ for currency. "
            "When suggesting investments, mention both risks and potential returns. "
            "If web data is provided, cite sources.\n\n"
            f"{financial_context}"
            f"{web_context}"
        )
        
        # Step 3: Stream LLM response
        yield f"event: status\ndata: {json.dumps({'phase': 'generating', 'message': 'Generating response...'})}\n\n"
        
        full_response = ""
        for chunk in llm.stream_response(user_query, system_prompt):
            full_response += chunk
            yield f"event: token\ndata: {json.dumps({'text': chunk})}\n\n"
        
        # Step 4: Store chat history
        if HAS_SUPABASE and user_id:
            supa.store_chat_message(user_id, "user", user_query)
            supa.store_chat_message(user_id, "assistant", full_response)
        
        yield f"event: done\ndata: {json.dumps({'total_length': len(full_response)})}\n\n"
    
    return StreamingResponse(generate_sse(), media_type="text/event-stream")


@app.get("/api/ai/history")
async def ai_chat_history(user_id: str):
    """Get AI chat history for a user."""
    if not HAS_SUPABASE:
        return {"history": []}
    
    history = supa.get_chat_history(user_id)
    return {"history": history}


# ═══════════════════════════════════════════════════════════════════════
# LEGACY ENDPOINT (backward compat)
# ═══════════════════════════════════════════════════════════════════════

@app.post("/ask/stream")
async def ask_llm_stream(request: PromptRequest):
    if not llm:
        raise HTTPException(status_code=503, detail="LLM not available")
    try:
        return StreamingResponse(
            llm.stream_response(request.prompt, request.system_prompt),
            media_type="text/plain"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)