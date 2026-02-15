"""
main.py — FinSight Backend API
================================
Serves SMS processing, transaction extraction, analytics, and LLM endpoints.
"""

import os
import sys
import json
from datetime import datetime
from typing import Optional, List, Any

from ollama_model import OllamaModel
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

app = FastAPI(title="FinSight API", version="2.0")
llm = OllamaModel(model_name="vicuna:13b")

# ─── Storage ────────────────────────────────────────────────────────────
DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
os.makedirs(DATA_DIR, exist_ok=True)

SMS_RAW_FILE = os.path.join(os.path.dirname(__file__), "sms_data.json")
TRANSACTIONS_FILE = os.path.join(DATA_DIR, "transactions.json")
PROCESSED_FILE = os.path.join(DATA_DIR, "processed_sms.json")


def _load_json(path: str) -> list:
    if os.path.exists(path):
        with open(path, "r") as f:
            return json.load(f)
    return []


def _save_json(path: str, data: list):
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


# ─── Models ─────────────────────────────────────────────────────────────
class SmsPayload(BaseModel):
    data: List[Any]


class PromptRequest(BaseModel):
    prompt: str
    system_prompt: Optional[str] = "You are a helpful assistant."


# ═══════════════════════════════════════════════════════════════════════
# SMS ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════

@app.post("/api/sms")
async def receive_sms(payload: SmsPayload):
    """
    Receive SMS from Flutter app, process through ML pipeline, and store.
    Automatically classifies, extracts transactions, and detects fraud.
    """
    try:
        sms_list = payload.data
        if not sms_list:
            return {"status": "ok", "message": "No SMS to process", "count": 0}

        # Store raw SMS
        existing_raw = _load_json(SMS_RAW_FILE)
        existing_raw.extend(sms_list)
        _save_json(SMS_RAW_FILE, existing_raw)

        # Process through pipeline
        processed = []
        transactions = []
        spam_count = 0

        existing_transactions = _load_json(TRANSACTIONS_FILE)

        for sms in sms_list:
            # Step 1: Classify & preprocess
            enriched = preprocess_single_sms(sms)
            
            # Step 2: Fraud/spam detection
            fraud_result = analyze_sms(sms)
            enriched['is_spam'] = fraud_result['is_spam']
            enriched['is_genuine'] = fraud_result['is_genuine']
            enriched['fraud_type'] = fraud_result.get('fraud_type')
            
            if fraud_result['is_spam']:
                spam_count += 1
            
            processed.append(enriched)
            
            # Step 3: Extract transaction details (only for financial_transaction)
            if enriched.get('label') == 'financial_transaction' and enriched.get('is_genuine', True):
                txn = extract_transaction(sms)
                
                # Post-extraction validation: skip if no valid transaction type
                if txn.get('transaction_type') is None:
                    continue
                    
                txn['label'] = enriched['label']
                txn['sub_label'] = enriched['sub_label']
                txn['label_confidence'] = enriched['label_confidence']
                
                # Anomaly detection
                anomaly = detect_anomaly(txn, existing_transactions)
                txn['is_anomaly'] = anomaly['is_anomaly']
                txn['anomaly_score'] = anomaly['anomaly_score']
                
                transactions.append(txn)

        # Save processed data
        existing_processed = _load_json(PROCESSED_FILE)
        existing_processed.extend(processed)
        _save_json(PROCESSED_FILE, existing_processed)

        # Save transactions
        existing_transactions.extend(transactions)
        _save_json(TRANSACTIONS_FILE, existing_transactions)

        print(f"[SMS API] Received {len(sms_list)} SMS | "
              f"{len(transactions)} transactions | {spam_count} spam | "
              f"{datetime.now().strftime('%H:%M:%S')}")

        return {
            "status": "ok",
            "message": f"Processed {len(sms_list)} SMS",
            "count": len(sms_list),
            "transactions_found": len(transactions),
            "spam_detected": spam_count,
            "total_raw": len(existing_raw),
            "total_transactions": len(existing_transactions),
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
async def get_transactions():
    """Get all extracted transactions."""
    data = _load_json(TRANSACTIONS_FILE)
    return {"data": data, "count": len(data)}


@app.post("/api/sms/process")
async def reprocess_all_sms():
    """Re-process all stored raw SMS through the ML pipeline."""
    try:
        raw_sms = _load_json(SMS_RAW_FILE)
        if not raw_sms:
            return {"status": "ok", "message": "No SMS to process"}

        processed = []
        transactions = []
        spam_count = 0

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
                
                # Post-extraction validation: skip if no valid transaction type
                if txn.get('transaction_type') is None:
                    continue
                    
                txn['label'] = enriched['label']
                txn['sub_label'] = enriched['sub_label']
                txn['label_confidence'] = enriched['label_confidence']
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
# ANALYTICS ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════

@app.get("/api/analytics")
async def get_analytics(
    period: str = Query(default="monthly", pattern="^(weekly|monthly|quarterly|yearly)$")
):
    """
    Get financial analytics for all transactions.
    
    Query params:
        period: 'weekly', 'monthly', 'quarterly', 'yearly'
    """
    transactions = _load_json(TRANSACTIONS_FILE)
    analytics = compute_analytics(transactions, period)
    return analytics


@app.get("/api/analytics/summary")
async def get_analytics_summary():
    """Get quick summary of all analytics periods."""
    transactions = _load_json(TRANSACTIONS_FILE)
    
    return {
        "weekly": compute_analytics(transactions, "weekly"),
        "monthly": compute_analytics(transactions, "monthly"),
        "quarterly": compute_analytics(transactions, "quarterly"),
        "yearly": compute_analytics(transactions, "yearly"),
    }


# ═══════════════════════════════════════════════════════════════════════
# LLM ENDPOINTS (existing)
# ═══════════════════════════════════════════════════════════════════════

@app.post("/ask/stream")
async def ask_llm_stream(request: PromptRequest):
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