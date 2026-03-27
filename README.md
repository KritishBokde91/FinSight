# FinSight

FinSight is an AI-assisted personal finance intelligence system built for Indian digital transaction ecosystems. The project combines a Flutter mobile application, a FastAPI backend, a hybrid machine learning pipeline, rule-based financial SMS understanding, transaction extraction, fraud screening, analytics generation, and an AI insights layer powered by a local LLM.

The core idea of the project is to convert raw financial SMS messages and UPI-related notifications into structured financial knowledge. Instead of asking users to enter expenses manually, FinSight automatically reads transaction-related signals from device messages, classifies them, extracts meaningful fields, stores them in structured form, and presents analytics and personalized financial insights through a mobile interface.

## Abstract

FinSight addresses a practical problem in personal finance management: most users receive rich transactional information through SMS and payment notifications, but that information remains unstructured and difficult to analyze at scale. This project proposes an end-to-end system that captures such data from a mobile device, processes it through a hybrid rule-based and machine learning pipeline, extracts transaction semantics, detects suspicious content, generates analytics, and exposes the results through a user-facing application.

The system is especially suitable for academic and research discussion because it brings together:

- mobile data acquisition from real-world financial messages
- weakly supervised labeling using domain-specific rules
- machine learning classification for ambiguous cases
- structured information extraction from semi-structured SMS text
- fraud and anomaly screening
- financial analytics and AI-assisted interpretation

## Research Motivation

Financial SMS messages are a valuable source of transactional data, but they are noisy, semi-structured, bank-specific, and mixed with non-transactional content such as OTPs, offers, loan advertisements, reminders, and spam. A useful financial intelligence system therefore needs to solve several problems together:

- distinguish genuine financial transactions from non-transactional messages
- separate alerts, OTPs, promotions, personal messages, and spam
- extract fields such as amount, transaction type, bank, payment method, and counterparty
- aggregate transaction streams into meaningful analytics
- support adaptive learning as more SMS data becomes available

FinSight is designed around this full pipeline rather than treating classification as an isolated task.

## System Objectives

- automate personal transaction tracking using SMS and UPI signals
- reduce manual expense entry for users
- build a reusable machine learning pipeline for financial SMS understanding
- provide a research-oriented architecture that can be evaluated, extended, and documented in a paper
- support real-time and batch processing through a mobile app plus backend API

## High-Level Architecture

FinSight has five main layers:

1. `Flutter mobile client`
   Reads SMS data from the device, triggers sync, shows dashboards, transactions, analytics, AI insights, and profile data.

2. `FastAPI backend`
   Accepts SMS batches and notifications, runs the processing pipeline, stores processed outputs, serves analytics, handles authentication, and exposes ML/AI endpoints.

3. `Hybrid ML pipeline`
   Performs preprocessing, weak-supervision labeling, fallback ML classification, transaction extraction, fraud checks, and analytics computation.

4. `AI insights layer`
   Uses Ollama with the `vicuna:13b` model for chat-style financial insights, with optional web crawling for current financial queries.

5. `Storage layer`
   Uses JSON files as a local fallback and supports Supabase-backed storage and authentication for user-scoped data.

## Technology Stack

### Mobile Application

- Flutter
- Dart
- `permission_handler`
- `shared_preferences`
- `flutter_background_service`
- `flutter_local_notifications`
- `fl_chart`
- `google_fonts`
- `flutter_animate`
- custom Android SMS access through platform channels

### Backend and API

- Python
- FastAPI
- Uvicorn
- Pydantic
- JSON-based local persistence
- optional Supabase integration for auth, storage, transactions, and chat history

### Machine Learning and Data Processing

- scikit-learn
- XGBoost
- pandas
- numpy
- joblib
- TF-IDF vectorization
- ensemble classification with XGBoost + Random Forest soft voting

### AI Layer

- Ollama
- Vicuna 13B
- streaming responses through Server-Sent Events
- optional web search and extraction using DuckDuckGo and Trafilatura-based crawling

## What Is Implemented

### Flutter App Summary

The Flutter app is the user-facing layer of FinSight. It handles login and signup, requests SMS and notification permissions, performs manual and background sync, and presents the processed financial data in a polished mobile UI. The app includes:

- authentication screen with login and signup
- dashboard with recent transactions and monthly net flow summary
- transactions screen with search, time filters, and category filters
- analytics screen with spending trend, category breakdown, income-vs-expense trends, payment method distribution, and top merchants
- AI insights screen with streaming financial chat responses
- profile screen showing user and system information
- background SMS synchronization every 15 minutes
- UPI notification synchronization through notification data forwarding

The Flutter layer is intentionally lightweight from a research perspective; most of the project novelty and technical contribution lies in the machine learning and backend pipeline.

### Backend Features

The backend inside `ML_Model/` is not only a model folder; it is the main processing server for the whole project. Implemented features include:

- email-based signup and login
- Supabase-first auth with local file fallback
- SMS ingestion endpoint for batch device sync
- raw SMS deduplication using message IDs
- transaction deduplication using SHA-256 content hashing
- transaction retrieval and category update endpoints
- analytics endpoints for weekly, monthly, quarterly, and yearly summaries
- ML training status and manual retraining endpoints
- AI chat endpoint with SSE token streaming
- chat history persistence through Supabase when available
- JSON fallback storage for offline/local development

### ML and Data Intelligence Features

The ML component is the core of the system. The current codebase implements:

- SMS cleaning and normalization
- engineered feature extraction from text and sender patterns
- automatic weak-supervision labeling for Indian financial SMS
- hybrid classification with rule-first inference and ML fallback for low-confidence cases
- extraction of amount, transaction direction, account/card details, payment method, bank, reference number, date, balance, and counterparty
- spam and phishing detection using domain rules
- transaction anomaly scoring using statistical heuristics over user history
- financial analytics generation from structured transaction records
- automatic retraining after a configurable volume of new SMS

## Machine Learning Methodology

This section is intentionally more detailed because it is the part most useful for research paper writing.

### 1. Problem Formulation

The project treats financial SMS understanding as a multi-stage intelligence problem rather than a single classifier. A message first needs to be cleaned, labeled, validated as genuine or suspicious, converted into structured transaction data if applicable, and then aggregated into user-level analytics.

### 2. Weak-Supervision Bootstrap Strategy

FinSight currently uses a rule-based labeler to generate initial labels for training data. This is important academically because the training pipeline is not based on a manually annotated benchmark alone. Instead, the system uses domain knowledge about Indian banking and payment SMS formats to bootstrap a labeled dataset.

The labeler classifies each SMS into one of six main categories:

- `financial_transaction`
- `financial_alert`
- `otp`
- `promotional`
- `personal`
- `spam`

This rule-based stage recognizes sender patterns, amount patterns, bank/account indicators, payment method references, OTP markers, promotion language, and fraud signals. It also explicitly blocks many non-transactional financial messages such as bill reminders, statements, or balance notifications from being mistaken as money-movement events.

From a research viewpoint, this is a weak-supervision approach: domain rules provide pseudo-labels that are then used to train a statistical classifier.

### 3. Preprocessing and Feature Engineering

For every SMS, the preprocessing layer:

- removes URLs and extra whitespace
- normalizes the message body
- computes text-level features such as body length and word count
- detects presence of amounts, account references, credit/debit language, balances, and URLs
- detects payment rails such as UPI, NEFT, IMPS, RTGS, card, and wallet indicators
- derives sender-level features such as bank sender pattern, shortcode sender, and phone-number sender
- computes a financial keyword count

This creates a structured feature representation that complements the raw text vectorization stage.

### 4. Hybrid Classification Architecture

The classification design is hybrid by construction:

- `Stage 1: rule-based inference`
  The SMS is first classified using the domain labeler.

- `Stage 2: ML fallback`
  If the rule-based confidence falls below `0.65` and a trained model is available, the system runs the machine learning model and compares confidence.

The machine learning model uses:

- TF-IDF vectorization with up to `5000` features
- `1-gram` to `3-gram` text representation
- hand-crafted structured features appended to the text representation
- XGBoost classifier
- Random Forest classifier
- soft-voting ensemble for final ML prediction
- 5-fold stratified cross-validation during training

This hybrid design is useful for research because it combines interpretability and domain coverage from rules with adaptability from machine learning.

### 5. Transaction Extraction

Once a message is identified as a genuine financial transaction, the extractor converts semi-structured SMS text into a structured transaction object. The implemented extractor parses:

- amount
- credit or debit direction
- account or card identifier
- bank name
- UPI/reference number
- payment method
- transaction date
- balance after transaction
- merchant or counterparty

This stage is critical because the downstream analytics do not operate on raw messages; they operate on normalized transaction records.

### 6. Fraud and Anomaly Screening

FinSight contains two safety-oriented checks:

- `Spam and phishing detection`
  Detects lottery scams, fake KYC alerts, suspicious links, OTP theft attempts, and misleading financial content.

- `Transaction anomaly scoring`
  Scores transactions using user-history heuristics such as unusually large amounts, debit bursts within short time windows, and previously unseen counterparties.

This makes the system more useful than a standard SMS classifier because it also considers trust and abnormality.

### 7. Analytics Layer

After extraction, the analytics engine computes:

- total transactions, credits, and debits
- total credited and debited amounts
- net flow
- average credit and debit values
- largest credit and debit values
- weekly, monthly, quarterly, and yearly breakdowns
- payment method breakdown
- bank-wise breakdown
- top counterparties or merchants

These analytics are exposed through the backend and visualized inside the Flutter app.

### 8. Continuous Learning

The project includes an automatic retraining module that monitors the incoming SMS volume and triggers model retraining after a threshold of new messages. In the current implementation:

- retraining threshold: `200` new SMS
- periodic check interval: `5` minutes
- saved artifacts include vectorizer, classifier, label encoder, metrics, and training status

This supports the research idea of a system that improves over time instead of staying fixed after initial deployment.

## Current Training Results

Based on the training artifacts currently present in the repository:

- total SMS used in the latest recorded training run: `3005`
- cross-validation accuracy: `99.93%`
- cross-validation standard deviation: `0.08%`
- weighted F1-score: `1.00`
- training accuracy: `1.00`
- latest recorded training date: `2026-02-15`

The class distribution stored in the metrics file includes:

- `financial_alert`: 328
- `financial_transaction`: 789
- `otp`: 52
- `personal`: 155
- `promotional`: 1679
- `spam`: 2

## Research Note on Results

These metrics are strong for the current project dataset, but they should be presented carefully in a research paper. The present pipeline uses rule-generated labels for bootstrap supervision, and the `spam` class has very low support in the current stored metrics. So the current numbers are best described as strong internal project results rather than final claims of real-world generalization.

That honest framing will make your paper stronger.

## End-to-End Workflow

1. The Flutter app reads device SMS and pending UPI-related notification data.
2. The app sends data in batches to the FastAPI backend.
3. The backend deduplicates raw SMS and stores them.
4. Each new message is preprocessed and weakly labeled.
5. Genuine financial transactions are extracted into structured records.
6. Fraud and anomaly checks are applied.
7. Structured transactions are stored and served through API endpoints.
8. The analytics engine computes summaries and trends.
9. The Flutter app displays dashboards, lists, charts, and AI-generated insights.
10. The auto-trainer monitors new SMS volume and retrains the model when thresholds are reached.

## Project Structure

```text
Final_Year_Project/
├── README.md
├── ML_MODEL_SUMMARY.md
├── ML_Model/
│   ├── main.py
│   ├── train.py
│   ├── auto_trainer.py
│   ├── ollama_model.py
│   ├── web_crawler.py
│   ├── requirements.txt
│   ├── pipeline/
│   │   ├── preprocessor.py
│   │   ├── labeler.py
│   │   ├── classifier.py
│   │   ├── extractor.py
│   │   ├── fraud_detector.py
│   │   └── analytics.py
│   ├── data/
│   └── models/
├── finsight/
│   ├── lib/
│   │   ├── screens/
│   │   ├── services/
│   │   ├── models/
│   │   └── core/
│   └── local_plugins/
└── supabase/
```

## Running the Project

### Backend

```bash
cd ML_Model
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8080 --reload
```

### Training the ML Model

```bash
cd ML_Model
python train.py
```

### Flutter App

```bash
cd finsight
flutter pub get
flutter run
```

Before running the Flutter app on a physical device, update the backend IP in `finsight/lib/core/constants.dart` so the phone can reach the FastAPI server on the same network.

### Optional Supabase

The repository also includes a `supabase/` setup for self-hosted Supabase services. Supabase is optional in the current architecture because the system can fall back to local JSON storage when cloud services are unavailable.

## Research Contribution Summary

For a final-year project or research paper, FinSight can be positioned as:

- a hybrid financial SMS intelligence framework for Indian transaction ecosystems
- a weakly supervised pipeline for turning raw SMS into structured personal finance data
- a practical combination of mobile sensing, NLP, information extraction, analytics, and AI assistance
- a deployable prototype that connects real device data with machine learning and user-facing financial decision support

In short, the Flutter app demonstrates usability, but the major research contribution is the ML-driven transformation of raw financial messages into structured analytics and intelligent insights.

## Conclusion

FinSight is more than a budgeting app. It is an end-to-end intelligent financial signal processing system that captures device-level transaction evidence, classifies and structures it, analyzes it, and turns it into actionable financial understanding. That makes it a strong foundation for both product development and an academic research paper centered on machine learning for financial text intelligence.
