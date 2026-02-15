"""
supabase_client.py — Supabase Database Client
===============================================
Handles all Supabase interactions: user management, SMS dedup,
transaction storage, and ML training log.
"""

import os
from dotenv import load_dotenv
from supabase import create_client, Client

# Load .env from ML_Model directory
load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))

# ─── Configuration ──────────────────────────────────────────────────────
# Self-hosted Supabase runs Kong on port 8001
SUPABASE_URL = os.getenv("SUPABASE_URL", "http://localhost:8001")
SUPABASE_SERVICE_KEY = os.getenv(
    "SUPABASE_SERVICE_KEY",
)
SUPABASE_ANON_KEY = os.getenv( 

    "SUPABASE_ANON_KEY",
)

# ─── Client Singleton ───────────────────────────────────────────────────
_client: Client = None


def get_client() -> Client:
    """Get or create Supabase client (service role for backend ops)."""
    global _client
    if _client is None:
        _client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
        print(f"[Supabase] Connected to {SUPABASE_URL}")
    return _client


# ═══════════════════════════════════════════════════════════════════════
# USER MANAGEMENT (GoTrue Auth + custom users table)
# ═══════════════════════════════════════════════════════════════════════

def auth_signup(email: str, password: str,
                display_name: str = None) -> dict:
    """
    Create user via GoTrue Admin API (appears in Auth dashboard)
    and also insert into custom users table for data referencing.
    """
    client = get_client()
    
    # Step 1: Create GoTrue auth user with email
    try:
        auth_result = client.auth.admin.create_user({
            "email": email,
            "password": password,
            "email_confirm": True,  # Auto-confirm
            "user_metadata": {
                "display_name": display_name or email.split('@')[0],
            },
        })
        
        gotrue_id = auth_result.user.id
        print(f"[Supabase Auth] GoTrue user created: {gotrue_id}")
    except Exception as e:
        error_msg = str(e)
        print(f"[Supabase Auth] GoTrue creation error: {error_msg}")
        # If user already exists in GoTrue, try to find them
        if "already been registered" in error_msg or "already exists" in error_msg:
            try:
                users_list = client.auth.admin.list_users()
                for u in users_list:
                    if getattr(u, 'email', None) == email:
                        gotrue_id = u.id
                        print(f"[Supabase Auth] Found existing GoTrue user: {gotrue_id}")
                        break
                else:
                    raise Exception("User exists in GoTrue but could not find them")
            except Exception as e2:
                print(f"[Supabase Auth] Could not find existing user: {e2}")
                return {}
        else:
            return {}
    
    # Step 2: Insert into custom users table (for FK references)
    user_data = {
        "id": str(gotrue_id),
        "email": email,
        "display_name": display_name or email.split('@')[0],
    }
    
    try:
        result = client.table("users").upsert(
            user_data, on_conflict="id"
        ).execute()
        db_user = result.data[0] if result.data else user_data
    except Exception as e:
        print(f"[Supabase] Users table insert error: {e}")
        db_user = user_data
    
    return db_user


def auth_login(email: str, password: str) -> dict:
    """
    Login via GoTrue Auth API using email.
    Returns user dict or empty dict on failure.
    """
    client = get_client()
    
    try:
        result = client.auth.sign_in_with_password({
            "email": email,
            "password": password,
        })
        
        user = result.user
        gotrue_id = str(user.id)
        metadata = user.user_metadata or {}
        
        # Update last_login in custom table
        try:
            from datetime import datetime
            client.table("users").update(
                {"last_login": datetime.now().isoformat()}
            ).eq("id", gotrue_id).execute()
        except Exception:
            pass
        
        return {
            "id": gotrue_id,
            "email": user.email,
            "display_name": metadata.get("display_name", email.split('@')[0]),
        }
    except Exception as e:
        print(f"[Supabase Auth] Login error: {e}")
        return {}


def get_user_by_id(user_id: str) -> dict:
    """Get user from custom users table."""
    client = get_client()
    try:
        result = client.table("users").select("*").eq("id", user_id).execute()
        return result.data[0] if result.data else {}
    except Exception as e:
        print(f"[Supabase] Get user error: {e}")
        return {}


# ═══════════════════════════════════════════════════════════════════════
# SMS STORAGE (with dedup)
# ═══════════════════════════════════════════════════════════════════════

def store_sms_batch(user_id: str, sms_list: list) -> int:
    """
    Store SMS batch with dedup via ON CONFLICT.
    Returns count of newly inserted SMS.
    """
    client = get_client()
    new_count = 0
    
    for sms in sms_list:
        row = {
            "user_id": user_id,
            "sms_id": str(sms.get("_id", "")),
            "thread_id": str(sms.get("thread_id", "")),
            "sender": sms.get("address", ""),
            "body": sms.get("body", ""),
            "sms_type": str(sms.get("type", "")),
            "timestamp": sms.get("date"),
            "date_sent": sms.get("date_sent"),
            "read": sms.get("read") == "1",
            "service_center": sms.get("service_center", ""),
            "label": sms.get("label", ""),
            "sub_label": sms.get("sub_label", ""),
            "label_confidence": sms.get("label_confidence", 0),
            "is_spam": sms.get("is_spam", False),
            "is_genuine": sms.get("is_genuine", True),
        }
        
        try:
            result = client.table("sms_messages").upsert(
                row, on_conflict="user_id,sms_id"
            ).execute()
            if result.data:
                new_count += 1
        except Exception as e:
            print(f"[Supabase] SMS insert error: {e}")
    
    return new_count


def get_user_sms_count(user_id: str) -> int:
    """Get total SMS count for a user."""
    client = get_client()
    result = client.table("sms_messages").select("id", count="exact").eq("user_id", user_id).execute()
    return result.count or 0


# ═══════════════════════════════════════════════════════════════════════
# TRANSACTION STORAGE
# ═══════════════════════════════════════════════════════════════════════

def store_transaction(user_id: str, txn: dict) -> dict:
    """Store a single transaction with dedup."""
    client = get_client()
    
    row = {
        "user_id": user_id,
        "sms_id": txn.get("sms_id", ""),
        "sender": txn.get("sender", ""),
        "receiver": txn.get("receiver", txn.get("counterparty", "")),
        "amount": txn.get("amount"),
        "transaction_type": txn.get("transaction_type"),
        "payment_method": txn.get("payment_method"),
        "category": txn.get("category", "other"),
        "category_edited": txn.get("category_edited", False),
        "bank_name": txn.get("bank_name"),
        "account_number": txn.get("account_number"),
        "counterparty": txn.get("counterparty"),
        "description": txn.get("description"),
        "raw_body": txn.get("raw_body"),
        "label": txn.get("label"),
        "sub_label": txn.get("sub_label"),
        "label_confidence": txn.get("label_confidence"),
        "is_anomaly": txn.get("is_anomaly", False),
        "anomaly_score": txn.get("anomaly_score", 0),
    }
    
    # Parse transaction date
    txn_date = txn.get("transaction_date")
    if txn_date:
        row["transaction_date"] = txn_date
    
    try:
        result = client.table("transactions").upsert(
            row, on_conflict="user_id,sms_id"
        ).execute()
        return result.data[0] if result.data else {}
    except Exception as e:
        print(f"[Supabase] Transaction insert error: {e}")
        return {}


def store_transactions_batch(user_id: str, transactions: list) -> int:
    """Store a batch of transactions. Returns count stored."""
    count = 0
    for txn in transactions:
        result = store_transaction(user_id, txn)
        if result:
            count += 1
    return count


def get_user_transactions(user_id: str, limit: int = 500) -> list:
    """Get all transactions for a user, ordered by date desc."""
    client = get_client()
    result = (client.table("transactions")
              .select("*")
              .eq("user_id", user_id)
              .order("transaction_date", desc=True)
              .limit(limit)
              .execute())
    return result.data or []


def update_transaction_category(txn_id: int, category: str, user_id: str) -> dict:
    """Update transaction category (user-edited)."""
    client = get_client()
    result = (client.table("transactions")
              .update({"category": category, "category_edited": True})
              .eq("id", txn_id)
              .eq("user_id", user_id)
              .execute())
    return result.data[0] if result.data else {}


def get_categories() -> list:
    """Get all available categories."""
    client = get_client()
    result = client.table("categories").select("*").order("name").execute()
    return result.data or []


# ═══════════════════════════════════════════════════════════════════════
# ML TRAINING LOG
# ═══════════════════════════════════════════════════════════════════════

def log_training(total_sms: int, accuracy: float, f1: float,
                 triggered_by: str, new_sms_count: int) -> dict:
    """Log a training run."""
    client = get_client()
    result = client.table("ml_training_log").insert({
        "total_sms_trained": total_sms,
        "accuracy": accuracy,
        "f1_score": f1,
        "triggered_by": triggered_by,
        "new_sms_count": new_sms_count,
    }).execute()
    return result.data[0] if result.data else {}


def get_last_training() -> dict:
    """Get the most recent training log entry."""
    client = get_client()
    result = (client.table("ml_training_log")
              .select("*")
              .order("trained_at", desc=True)
              .limit(1)
              .execute())
    return result.data[0] if result.data else {}


def get_total_sms_since_training() -> int:
    """Get count of SMS received since last training."""
    last = get_last_training()
    if not last:
        return 0
    
    client = get_client()
    result = (client.table("sms_messages")
              .select("id", count="exact")
              .gt("processed_at", last["trained_at"])
              .execute())
    return result.count or 0


# ═══════════════════════════════════════════════════════════════════════
# AI CHAT STORAGE
# ═══════════════════════════════════════════════════════════════════════

def store_chat_message(user_id: str, role: str, content: str,
                       web_sources: list = None) -> dict:
    """Store a chat message."""
    client = get_client()
    result = client.table("ai_conversations").insert({
        "user_id": user_id,
        "role": role,
        "content": content,
        "web_sources": web_sources or [],
    }).execute()
    return result.data[0] if result.data else {}


def get_chat_history(user_id: str, limit: int = 20) -> list:
    """Get recent chat history for a user."""
    client = get_client()
    result = (client.table("ai_conversations")
              .select("*")
              .eq("user_id", user_id)
              .order("created_at", desc=True)
              .limit(limit)
              .execute())
    return list(reversed(result.data or []))
