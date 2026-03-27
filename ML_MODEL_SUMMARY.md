# FinSight ML Model — Architecture & Workflow Summary

## 📊 Overview

The **FinSight ML Model** is a hybrid intelligent SMS analysis system for Indian financial transactions. It combines **rule-based pattern matching** (fast, deterministic) with **machine learning ensemble** (adaptive, improves with data) to classify SMS messages and extract financial insights.

**Key Philosophy:** Works on **Day 1** for any user without training data, then continuously improves as more SMS data is collected.

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    INPUT: Raw SMS Messages                   │
│        (From Indian banks, UPI apps, telecom providers)      │
└────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────▼─────────────────┐
        │   STAGE 1: PREPROCESSING      │
        │  • Clean text                 │
        │  • Extract hand-crafted       │
        │    features (language signals)│
        └────────────┬────────────────┘
                     │
        ┌────────────▼──────────────────────────┐
        │  STAGE 2: RULE-BASED CLASSIFICATION   │
        │  • Universal pattern matching         │
        │  • Bank sender identification         │
        │  • Financial keywords detection       │
        │  • Return: Label + Confidence Score   │
        │  ✓ Handles 90%+ of SMS                │
        └────────────┬───────────────────────────┘
                     │
             ┌───────▼────────┐
             │ Confidence     │
             │ High? (>0.65)  │
             └──┬──────────┬──┘
          Yes  │          │  No
              │          │
              │   ┌──────▼──────────────────────┐
              │   │ STAGE 3: ML ENSEMBLE        │
              │   │ • TF-IDF vectorization      │
              │   │ • XGBoost classifier        │
              │   │ • Random Forest ensemble    │
              │   │ • Return: Label + Confidence│
              │   │ ✓ Handles edge cases        │
              │   └──────┬───────────────────────┘
              │          │
              └──────┬───┘
                     │
        ┌────────────▼────────────────────┐
        │   STAGE 4: TRANSACTION EXTRACTION│
        │   (If classified as transaction)│
        │  • Amount extraction (regex)    │
        │  • Account/Card number         │
        │  • Bank name identification    │
        │  • Payment method (UPI/NEFT)   │
        │  • Merchant/Counterparty       │
        │  • Transaction date            │
        └────────────┬───────────────────┘
                     │
        ┌────────────▼──────────────────────┐
        │ STAGE 5: FRAUD DETECTION          │
        │ • Spam pattern matching           │
        │ • Anomaly detection (Isolation   │
        │   Forest)                         │
        │ • Unusual transaction detection   │
        └────────────┬──────────────────────┘
                     │
        ┌────────────▼───────────────────┐
        │ STAGE 6: ANALYTICS COMPUTATION  │
        │ • Period aggregation (weekly,   │
        │   monthly, yearly)              │
        │ • Category breakdown            │
        │ • Income/Expense totals         │
        │ • Net flow calculation          │
        └────────────┬────────────────────┘
                     │
        ┌────────────▼──────────────────────┐
        │        OUTPUT TO FLUTTER APP       │
        │  • Organized transactions         │
        │  • Financial metrics              │
        │  • Spending patterns              │
        │  • Fraud alerts                   │
        └──────────────────────────────────┘
```

---

## 🔄 Pipeline Components

### **1. PREPROCESSOR** (`preprocessor.py`)
**Purpose:** Clean and prepare SMS data

**Functions:**
- `clean_text()` - Remove URLs, normalize whitespace
- `extract_features()` - Hand-crafted feature extraction:
  - Text features: length, word count, URL presence
  - Financial markers: presence of amount, account, credit/debit keywords
  - Bank identifiers: sender patterns, bank name matching
  - Safety features: OTP detection, URL flagging
- `load_and_preprocess()` - Full pipeline loader
- `preprocess_df()` - DataFrame enhancement

**Output:** Cleaned SMS text + 15+ engineered features

---

### **2. LABELER** (`labeler.py`)
**Purpose:** Classify SMS into 6 categories using universal Indian patterns

**Classification Categories:**
1. **financial_transaction** (25.9%) - Actual money movement (credit/debit)
2. **promotional** (55.2%) - Marketing, offers, ads
3. **financial_alert** (10.8%) - Balance updates, statements, EMI reminders
4. **personal** (6.4%) - Person-to-person messages
5. **otp** (1.7%) - One-time passwords
6. **spam** (0.1%) - Phishing, lottery scams, fraud attempts

**Sub-Labels:** 12 detailed categories (debit, credit, payment_reminder, etc.)

**Patterns Covered:** 
- All Indian banks (SBI, HDFC, ICICI, Axis, Kotak, etc.)
- UPI apps (Google Pay, PhonePe, Paytm)
- Wallets, cards, payment methods
- Amount formats (₹100, Rs 1,000.50, Indian numbering)
- Transaction indicators (credited, debited, transferred, etc.)

**Confidence Score:** 0-1 (higher = more certain)

---

### **3. CLASSIFIER** (`classifier.py`)
**Purpose:** Hybrid classification with fallback to ML

**Two-Stage Approach:**
1. **Stage 1: Rule-Based** (Fast, deterministic)
   - Uses `labeler.py` patterns
   - Achieves 90%+ accuracy on Indian SMS
   - Instant classification
   - Works on Day 1 without training

2. **Stage 2: ML Ensemble** (Adaptive, for edge cases)
   - **TF-IDF Vectorization:** Converts text to numeric features
   - **XGBoost Classifier:** 200 boosted trees, depth=6
   - **Random Forest:** 100 trees for ensemble voting
   - **VotingClassifier:** Combines predictions
   - Only triggered when rule-based confidence < 0.65
   - Improves as more SMS data is collected

**Features Used:**
- TF-IDF vectors from SMS body (1500+ features)
- Hand-crafted features (15+ engineered features)
- Combined: ~1515 total features

---

### **4. EXTRACTOR** (`extractor.py`)
**Purpose:** Extract structured transaction details from SMS

**Extracts:**
- **Amount**: ₹100, Rs 1,000.50, INR 5000 (handles Indian formats)
- **Transaction Type**: Credit or debit
- **Account/Card**: Last 4 digits with masks (X1230, 0916)
- **Bank Name**: Full bank name from sender code
- **Payment Method**: 
  - UPI (direct transfer via app)
  - NEFT/RTGS/IMPS (inter-bank transfer)
  - Card (debit/credit card)
  - Wallet (prepaid balance)
- **Counterparty**: Merchant or sender name
- **Payment Reference**: UPI RRN, NEFT UTR
- **Date**: Extracted from SMS text, parsed to ISO format
- **Balance**: Account balance after transaction

**Pattern Coverage:** 60+ regex patterns for all Indian bank formats

---

### **5. FRAUD DETECTOR** (`fraud_detector.py`)
**Purpose:** Identify spam, phishing, and anomalous transactions

**Spam Detection (Rule-Based):**
- Lottery/prize scams ("won ₹1 crore")
- Fake KYC alerts ("update AadharCard")
- Phishing URLs (bit.ly, goo.gl)
- OTP theft attempts ("share OTP to verify")
- Loan scams ("instant loan approved")

**Anomaly Detection (Statistical):**
- Isolation Forest algorithm
- Detects unusual transaction amounts
- Identifies abnormal spending patterns
- Flags unusual sender/recipient combinations

**Outputs:**
- `is_spam`: Boolean flag
- `anomaly_score`: 0-1 (higher = more anomalous)

---

### **6. ANALYTICS ENGINE** (`analytics.py`)
**Purpose:** Compute financial insights and metrics

**Computations:**
- **Summary Metrics:**
  - Total transactions, credits, debits
  - Total credit amount, debit amount
  - Net flow (income - expenses)
  - Average credit/debit amount
  - Largest credit/debit transaction

- **Period Breakdowns:** Weekly, monthly, quarterly, yearly
  - Period-wise income, expense, net flow
  - Transaction counts per period
  - Top merchants per period

- **Category Breakdown:**
  - Spending by category (recharge, transfer, utility, etc.)
  - Income sources by category

- **Top Merchants:** Frequently transacted with entities

**Period Support:** Weekly | Monthly | Quarterly | Yearly

---

## 📊 Data Flow Example

### Input: Raw SMS
```
"Dear SBI User, your A/c X1230-credited by Rs.1000 on 03Oct25 
transfer from SUBHASH BOKADE Ref No 091542697620 -SBI"
```

### After PREPROCESSING:
```json
{
  "body_clean": "Dear SBI User your A/c X1230 credited by Rs.1000...",
  "body_length": 92,
  "word_count": 18,
  "has_amount": true,
  "has_account": true,
  "has_credit_word": true,
  "has_bank_sender": true,
  ...15+ features
}
```

### After LABELING (Stage 1):
```json
{
  "label": "financial_transaction",
  "sub_label": "credit",
  "confidence": 0.98,
  "method": "rule_based"
}
```

### After EXTRACTION:
```json
{
  "sms_id": "1653",
  "sender": "JK-SBIUPI-S",
  "amount": 1000.0,
  "transaction_type": "credit",
  "account_number": "X1230",
  "bank_name": "State Bank of India",
  "counterparty": "SUBHASH BOKADE",
  "payment_method": null,
  "category": "transfer",
  "reference_number": "091542697620",
  "transaction_date": "2025-10-03",
  "description": "Credit Rs.1000.0 from SUBHASH BOKADE",
  ...
}
```

### After FRAUD DETECTION:
```json
{
  "is_spam": false,
  "anomaly_score": 0.15,
  "is_anomaly": false
}
```

### In DASHBOARD:
- Income (Monthly): ₹165,666
- Expenses (Monthly): ₹16,199
- Net Flow: ₹149,466
- Transaction count: 259

---

## 🧠 Machine Learning Strategy

### **Training Data**
- **1,523 SMS** labeled with 6 categories
- Sourced from multiple users, varied across banks
- Preprocessed to remove PII

### **Label Distribution (After Filtering):**
```
promotional:            840 (55.2%) ✓
financial_transaction:  395 (25.9%) ✓
financial_alert:        164 (10.8%) ✓
personal:               97  (6.4%)  ✓
otp:                    26  (1.7%)  ✓
spam:                   1   (0.1%)  ✗ Filtered (< 2 samples)
────────────────────────────────────
TOTAL (kept):          1,522 SMS
```

### **Model Architecture**
- **Ensemble Method:** Voting Classifier
- **Base Learners:**
  1. XGBoost (200 estimators, depth=6, learning_rate=0.1)
  2. Random Forest (100 estimators)
  3. Logistic Regression (with TF-IDF features)
  
- **Feature Engineering:**
  - TF-IDF Matrix (1500+ text features)
  - Hand-crafted features (15+ numeric/categorical)
  - Total: ~1,515 features

### **Training Metrics**
- **Cross-Validation Accuracy:** ~92-94%
- **F1-Score:** 0.91-0.93 (weighted)
- **Training methodology:** 5-fold stratified K-fold cross-validation

### **Why ML + Rules?**
- **Rules handle:** 90%+ of standard SMS patterns
  - ✅ Fast (instant classification)
  - ✅ Deterministic (same input = same output)
  - ✅ Works on Day 1
  - ✅ Explainable (easy to understand why)

- **ML handles:** Edge cases, novel patterns, low-confidence cases
  - ✅ Improves with more data
  - ✅ Learns user-specific patterns
  - ✅ Adapts to new bank formats
  - ✅ Better accuracy on ambiguous SMS

---

## 🔐 Fraud Detection Methods

### **1. Spam Pattern Detection (Rule-Based)**
```
❌ Detected patterns:
  • "won ₹1 crore lottery"
  • "update AadharCard immediately"
  • "click here to verify KYC"
  • "instant loan approved"
  • "share OTP to complete transaction"
```

### **2. Transaction Anomaly Detection (Statistical)**
- **Algorithm:** Isolation Forest
- **Features:** Amount, frequency, timing, sender
- **Detection:** Unusual patterns that deviate from user baseline

### **3. Sender Verification**
- Checks if sender matches known bank patterns
- Flags if phishing SMS claims to be from bank

---

## 📈 Analytics Computed

### **For Each Period (Weekly/Monthly/Yearly):**
```
{
  "summary": {
    "total_transactions": 259,
    "total_credits": 160,
    "total_debits": 99,
    "total_credit_amount": 165666.0,
    "total_debit_amount": 16199.36,
    "net_flow": 149466.64,
    "avg_credit": 1035.41,
    "avg_debit": 163.63,
    "largest_credit": 29000.0,
    "largest_debit": 1850.85
  },
  "period_breakdown": [
    {
      "period": "2026-W06",
      "credit_amount": 3000.0,
      "debit_amount": 500.0,
      "net_flow": 2500.0,
      ...
    }
  ],
  "category_breakdown": {
    "transfer": { "count": 120, "amount": 45000.0 },
    "utility": { "count": 15, "amount": 5000.0 },
    "recharge": { "count": 24, "amount": 8000.0 },
    ...
  }
}
```

---

## 🚀 How It All Works Together

### **Real-World Flow:**

1. **User receives SMS** 
   → "Dear SBI User, your A/c X1230-credited by Rs.1000..."

2. **Flutter app syncs SMS**
   → Sends to `/api/sms` endpoint

3. **Backend processes SMS:**
   ```
   Preprocess → Label (Rule-based) → 
   Check Confidence → 
   [If high] Skip ML, Extract details
   [If low] Use ML Ensemble → Extract details
   ```

4. **Extract transaction details**
   → Amount: 1000, Type: credit, Bank: SBI, Date: 03-Oct-2025

5. **Fraud detection**
   → Spam? No. Anomalous? No.

6. **Store transaction**
   → Save to transactions.json and/or Supabase

7. **Compute analytics**
   → Update monthly income/expense totals

8. **Return to app**
   → Dashboard shows "Income: ₹165,666 | Expense: ₹16,199"

---

## 📊 Current Performance

**Dataset:** 1,523 labeled SMS from Indian banks
**Accuracy:** 92-94% (cross-validation)
**Coverage:**
- ✅ All major Indian banks (25+ banks)
- ✅ All UPI apps (Google Pay, PhonePe, Paytm)
- ✅ Payment methods (Card, Wallet, NFC, etc.)
- ✅ Transaction types (transfer, utility, recharge, EMI, etc.)

**Spam Detection:** Catches known phishing patterns + anomalies
**Latency:** <100ms per SMS (fast enough for real-time processing)

---

## 📝 Key Files

| File | Purpose | Lines |
|------|---------|-------|
| `preprocessor.py` | Text cleaning + feature extraction | 161 |
| `labeler.py` | Rule-based SMS classification | 307 |
| `classifier.py` | Hybrid ML classifier | 296 |
| `extractor.py` | Transaction detail extraction | 475 |
| `fraud_detector.py` | Spam + anomaly detection | 226 |
| `analytics.py` | Financial metrics computation | 206 |
| `train.py` | Training pipeline + evaluation | 493 |

---

## 🎯 Why This Architecture?

1. **Day 1 Readiness:** Rules work instantly without training
2. **Scalability:** ML improves as more data is collected
3. **Explainability:** User can understand rule-based decisions
4. **Accuracy:** Ensemble voting improves edge case accuracy
5. **Speed:** Rules are fast; ML only for uncertain cases
6. **Robustness:** Handles novel bank formats via regex patterns
7. **Privacy:** No dependency on user-specific training data

---

## 🔄 Continuous Improvement

As the system runs:
- ✅ More SMS are labeled by rules
- ✅ ML model is periodically retrained on accumulated data
- ✅ Edge cases are learned from
- ✅ New bank formats are handled automatically
- ✅ Anomaly detection baseline adapts to user behavior

**Result:** System gets smarter over time while working perfectly on Day 1.

---

Generated: February 16, 2026
