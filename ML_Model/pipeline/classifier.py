"""
classifier.py — SMS Classification Engine
==========================================
Hybrid classifier: Rule-based labeling + ML ensemble for edge cases.

The rule-based labeler handles 90%+ of cases with high confidence.
The ML model (TF-IDF + XGBoost) handles ambiguous cases where rule-based
confidence is below threshold.

This design ensures the system works on DAY ONE for ANY user without
needing their specific SMS data for training. The ML model continually
improves as more users sync their SMS.
"""

import os
import json
import joblib
import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.ensemble import VotingClassifier, RandomForestClassifier
from sklearn.model_selection import StratifiedKFold, cross_val_score
from sklearn.metrics import (
    classification_report, confusion_matrix,
    accuracy_score, f1_score
)

from xgboost import XGBClassifier
from typing import Tuple, Optional

from pipeline.labeler import label_sms
from pipeline.preprocessor import clean_text, extract_features

# ─── MODEL PATHS ─────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_DIR = os.path.join(BASE_DIR, 'models')
CLASSIFIER_PATH = os.path.join(MODELS_DIR, 'classifier.pkl')
VECTORIZER_PATH = os.path.join(MODELS_DIR, 'tfidf_vectorizer.pkl')

# Rule-based confidence threshold — below this, use ML model
CONFIDENCE_THRESHOLD = 0.65

class SmsClassifier:
    """
    Hybrid SMS classifier for Indian SMS.
    
    Stage 1: Rule-based labeling (fast, deterministic, works on ANY SMS)
    Stage 2: ML ensemble (for low-confidence cases, improves with data)
    """
    
    def __init__(self):
        self.vectorizer: Optional[TfidfVectorizer] = None
        self.model = None
        self.is_trained = False
        self._load_model()
    
    def _load_model(self):
        """Load pre-trained model if available."""
        if os.path.exists(CLASSIFIER_PATH) and os.path.exists(VECTORIZER_PATH):
            try:
                self.model = joblib.load(CLASSIFIER_PATH)
                self.vectorizer = joblib.load(VECTORIZER_PATH)
                self.is_trained = True
                print("[Classifier] Loaded pre-trained model")
            except Exception as e:
                print(f"[Classifier] Could not load model: {e}")
                self.is_trained = False
    
    def classify(self, body: str, sender: str = "") -> dict:
        """
        Classify a single SMS message.
        
        Returns dict with: label, sub_label, confidence, method
        """
        # Stage 1: Rule-based
        label, sub_label, confidence = label_sms(body, sender)
        
        result = {
            'label': label,
            'sub_label': sub_label,
            'confidence': round(confidence, 3),
            'method': 'rule_based'
        }
        
        # Stage 2: ML model for low-confidence cases
        if confidence < CONFIDENCE_THRESHOLD and self.is_trained:
            try:
                ml_label, ml_confidence = self._ml_predict(body, sender)
                if ml_confidence > confidence:
                    result['label'] = ml_label
                    result['confidence'] = round(ml_confidence, 3)
                    result['method'] = 'ml_ensemble'
                    # Keep sub_label from rule-based as ML only does broad labels
            except Exception as e:
                print(f"[Classifier] ML prediction error: {e}")
        
        return result
    
    def _ml_predict(self, body: str, sender: str) -> Tuple[str, float]:
        """Use ML model for prediction."""
        clean = clean_text(body)
        features_dict = extract_features(body, sender)
        
        # TF-IDF features
        tfidf_features = self.vectorizer.transform([clean])
        
        # Hand-crafted features
        feature_names = sorted(features_dict.keys())
        hand_features = np.array([[features_dict[f] for f in feature_names]])
        
        # Combine features
        from scipy.sparse import hstack
        combined = hstack([tfidf_features, hand_features])
        
        # Predict
        prediction = self.model.predict(combined)[0]
        probabilities = self.model.predict_proba(combined)[0]
        confidence = float(max(probabilities))
        
        return prediction, confidence
    
    def train(self, df: pd.DataFrame, save: bool = True) -> dict:
        """
        Train the ML ensemble on labeled data.
        
        Args:
            df: DataFrame with 'body_clean', 'label', and feature columns
            save: Whether to save trained model to disk
            
        Returns:
            dict with training metrics including XGBoost eval results
        """
        print("[Classifier] Training ML ensemble...")
        
        # Prepare text features with TF-IDF
        self.vectorizer = TfidfVectorizer(
            max_features=5000,
            ngram_range=(1, 3),
            min_df=2,
            max_df=0.95,
            sublinear_tf=True,
        )
        
        tfidf_matrix = self.vectorizer.fit_transform(df['body_clean'].fillna(''))
        
        # Hand-crafted features
        feature_cols = [c for c in df.columns if c.startswith(('has_', 'is_')) 
                       or c in ('body_length', 'word_count', 'financial_keyword_count')]
        hand_features = df[feature_cols].values.astype(float)
        
        # Combine
        from scipy.sparse import hstack
        X = hstack([tfidf_matrix, hand_features])
        y = df['label'].values
        
        # Encode labels
        from sklearn.preprocessing import LabelEncoder
        le = LabelEncoder()
        y_encoded = le.fit_transform(y)
        
        # ── Train/validation split for XGBoost eval metrics ──
        from sklearn.model_selection import train_test_split
        X_train, X_val, y_train, y_val = train_test_split(
            X, y_encoded, test_size=0.2, random_state=42, stratify=y_encoded
        )
        
        # ── Train XGBoost standalone first to capture per-round loss ──
        xgb = XGBClassifier(
            n_estimators=200,
            max_depth=6,
            learning_rate=0.1,
            use_label_encoder=False,
            eval_metric='mlogloss',
            random_state=42,
        )
        
        # Train with eval_set to capture loss per round
        xgb.fit(
            X_train, y_train,
            eval_set=[(X_train, y_train), (X_val, y_val)],
            verbose=False,
        )
        xgb_eval_results = xgb.evals_result()
        
        # Get feature importance from XGBoost
        tfidf_feature_names = self.vectorizer.get_feature_names_out().tolist()
        all_feature_names = tfidf_feature_names + feature_cols
        xgb_importance = xgb.feature_importances_
        
        # ── Now train ensemble on full data ──
        xgb_full = XGBClassifier(
            n_estimators=200,
            max_depth=6,
            learning_rate=0.1,
            use_label_encoder=False,
            eval_metric='mlogloss',
            random_state=42,
        )
        
        rf = RandomForestClassifier(
            n_estimators=200,
            max_depth=10,
            random_state=42,
            n_jobs=-1,
        )
        
        self.model = VotingClassifier(
            estimators=[('xgb', xgb_full), ('rf', rf)],
            voting='soft',
        )
        
        # Cross-validation
        cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
        cv_scores = cross_val_score(self.model, X, y_encoded, cv=cv, scoring='accuracy')
        
        print(f"[Classifier] Cross-val accuracy: {cv_scores.mean():.4f} ± {cv_scores.std():.4f}")
        
        # Train on full data
        self.model.fit(X, y_encoded)
        self.is_trained = True
        
        # Store label encoder for inverse transform
        self._label_encoder = le
        
        # Predictions for metrics
        y_pred = self.model.predict(X)
        
        # Get prediction probabilities for ROC/PR curves
        y_proba = self.model.predict_proba(X)
        
        metrics = {
            'cv_accuracy_mean': round(float(cv_scores.mean()), 4),
            'cv_accuracy_std': round(float(cv_scores.std()), 4),
            'cv_scores': [round(float(s), 4) for s in cv_scores],
            'train_accuracy': round(float(accuracy_score(y_encoded, y_pred)), 4),
            'f1_weighted': round(float(f1_score(y_encoded, y_pred, average='weighted')), 4),
            'classification_report': classification_report(
                y_encoded, y_pred, target_names=le.classes_, output_dict=True
            ),
            'confusion_matrix': confusion_matrix(y_encoded, y_pred).tolist(),
            'labels': le.classes_.tolist(),
            # New: XGBoost training curves data
            'xgb_eval_results': xgb_eval_results,
            'xgb_learning_rate': 0.1,
            'xgb_n_estimators': 200,
            # New: Feature importance
            'feature_names': all_feature_names,
            'feature_importance': xgb_importance.tolist(),
            # New: Prediction probabilities for ROC/PR curves
            'y_true': y_encoded.tolist(),
            'y_proba': y_proba.tolist(),
        }
        
        if save:
            os.makedirs(MODELS_DIR, exist_ok=True)
            joblib.dump(self.model, CLASSIFIER_PATH)
            joblib.dump(self.vectorizer, VECTORIZER_PATH)
            
            # Save label encoder
            joblib.dump(le, os.path.join(MODELS_DIR, 'label_encoder.pkl'))
            
            # Save metrics (without large arrays)
            save_metrics = {k: v for k, v in metrics.items() 
                          if k not in ('y_true', 'y_proba', 'feature_names', 'feature_importance')}
            with open(os.path.join(MODELS_DIR, 'training_metrics.json'), 'w') as f:
                json.dump(save_metrics, f, indent=2, default=str)
            
            print(f"[Classifier] Model saved to {MODELS_DIR}")
        
        return metrics
