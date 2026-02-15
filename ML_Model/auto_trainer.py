"""
auto_trainer.py — Automatic ML Model Retraining
=================================================
Monitors new SMS count and triggers retraining when threshold is met.
Runs as a background thread in the FastAPI server.
"""

import os
import sys
import json
import threading
import time
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

RETRAIN_THRESHOLD = 200  # Retrain after 200 new SMS
CHECK_INTERVAL = 300     # Check every 5 minutes
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SMS_RAW_FILE = os.path.join(BASE_DIR, "sms_data.json")
TRAINING_STATUS_FILE = os.path.join(BASE_DIR, "data", "training_status.json")


class AutoTrainer:
    """Background auto-retrainer that monitors for new SMS data."""
    
    def __init__(self):
        self.is_training = False
        self.last_trained_count = self._get_last_trained_count()
        self.last_accuracy = 0.0
        self._thread = None
        self._stop_event = threading.Event()
    
    def _get_last_trained_count(self) -> int:
        """Get the SMS count from the last training run."""
        status_file = TRAINING_STATUS_FILE
        if os.path.exists(status_file):
            with open(status_file, 'r') as f:
                status = json.load(f)
                return status.get('total_sms_trained', 0)
        return 0
    
    def _get_current_sms_count(self) -> int:
        """Get current total SMS count."""
        if os.path.exists(SMS_RAW_FILE):
            with open(SMS_RAW_FILE, 'r') as f:
                data = json.load(f)
                return len(data)
        return 0
    
    def get_status(self) -> dict:
        """Get current training status."""
        current_count = self._get_current_sms_count()
        new_since_training = current_count - self.last_trained_count
        
        return {
            'is_training': self.is_training,
            'last_trained_count': self.last_trained_count,
            'current_sms_count': current_count,
            'new_since_training': max(0, new_since_training),
            'threshold': RETRAIN_THRESHOLD,
            'progress_to_retrain': min(100, int(max(0, new_since_training) / RETRAIN_THRESHOLD * 100)),
            'last_accuracy': self.last_accuracy,
        }
    
    def should_retrain(self) -> bool:
        """Check if retraining threshold is met."""
        current = self._get_current_sms_count()
        new_count = current - self.last_trained_count
        return new_count >= RETRAIN_THRESHOLD and not self.is_training
    
    def retrain(self, triggered_by: str = 'threshold') -> dict:
        """Execute retraining pipeline."""
        if self.is_training:
            return {'status': 'already_training'}
        
        self.is_training = True
        print(f"\n[AutoTrainer] 🔄 Retraining triggered by: {triggered_by}")
        print(f"[AutoTrainer] SMS count: {self._get_current_sms_count()}")
        
        try:
            from pipeline.preprocessor import load_and_preprocess, export_csv
            from pipeline.classifier import SmsClassifier
            
            # Load and preprocess
            df = load_and_preprocess(SMS_RAW_FILE)
            csv_path = os.path.join(BASE_DIR, 'data', 'labeled_sms.csv')
            export_csv(df, csv_path)
            
            # Train
            classifier = SmsClassifier()
            metrics = classifier.train(df, save=True)
            
            current_count = self._get_current_sms_count()
            new_count = current_count - self.last_trained_count
            
            # Update status
            self.last_trained_count = current_count
            self.last_accuracy = metrics['cv_accuracy_mean']
            
            # Save training status
            status = {
                'total_sms_trained': current_count,
                'accuracy': metrics['cv_accuracy_mean'],
                'f1_score': metrics['f1_weighted'],
                'triggered_by': triggered_by,
                'new_sms_count': new_count,
                'trained_at': datetime.now().isoformat(),
            }
            
            os.makedirs(os.path.dirname(TRAINING_STATUS_FILE), exist_ok=True)
            with open(TRAINING_STATUS_FILE, 'w') as f:
                json.dump(status, f, indent=2)
            
            # Try to log to Supabase (if available)
            try:
                from supabase_client import log_training
                log_training(
                    total_sms=current_count,
                    accuracy=metrics['cv_accuracy_mean'],
                    f1=metrics['f1_weighted'],
                    triggered_by=triggered_by,
                    new_sms_count=new_count,
                )
            except Exception as e:
                print(f"[AutoTrainer] Supabase log failed (non-critical): {e}")
            
            print(f"[AutoTrainer] ✅ Retraining complete!")
            print(f"[AutoTrainer] Accuracy: {metrics['cv_accuracy_mean']:.4f}")
            print(f"[AutoTrainer] F1-Score: {metrics['f1_weighted']:.4f}")
            
            return {
                'status': 'completed',
                'accuracy': metrics['cv_accuracy_mean'],
                'f1_score': metrics['f1_weighted'],
                'total_trained': current_count,
                'new_sms': new_count,
            }
            
        except Exception as e:
            import traceback
            traceback.print_exc()
            return {'status': 'failed', 'error': str(e)}
        finally:
            self.is_training = False
    
    def _background_loop(self):
        """Background thread that checks retrain threshold periodically."""
        print(f"[AutoTrainer] 🚀 Background monitor started (threshold: {RETRAIN_THRESHOLD} SMS)")
        while not self._stop_event.is_set():
            if self.should_retrain():
                self.retrain(triggered_by='threshold')
            self._stop_event.wait(CHECK_INTERVAL)
    
    def start_background(self):
        """Start background monitoring thread."""
        if self._thread and self._thread.is_alive():
            return
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._background_loop, daemon=True)
        self._thread.start()
    
    def stop_background(self):
        """Stop background monitoring."""
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=5)


# Singleton instance
trainer = AutoTrainer()
