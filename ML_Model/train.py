"""
train.py — End-to-End Training & Visualization Script
======================================================
Runs the full pipeline: preprocess → label → train → evaluate → visualize.
Generates confusion matrix, ROC curves, feature importance, and label distribution.

Usage:
    python train.py
    python train.py --data path/to/sms_data.json
"""

import os
import sys
import json
import argparse
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import confusion_matrix, ConfusionMatrixDisplay

# Add parent dir to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pipeline.preprocessor import load_and_preprocess, export_csv
from pipeline.classifier import SmsClassifier
from pipeline.extractor import extract_transaction
from pipeline.fraud_detector import detect_spam


def main():
    parser = argparse.ArgumentParser(description='Train FinSight SMS Analysis Pipeline')
    parser.add_argument('--data', default='sms_data.json', help='Path to SMS JSON data')
    args = parser.parse_args()
    
    base_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(base_dir, 'data')
    results_dir = os.path.join(data_dir, 'training_results')
    os.makedirs(results_dir, exist_ok=True)
    os.makedirs(os.path.join(base_dir, 'models'), exist_ok=True)
    
    data_path = os.path.join(base_dir, args.data) if not os.path.isabs(args.data) else args.data
    
    print("=" * 70)
    print("  FinSight ML Pipeline — Training & Evaluation")
    print("=" * 70)
    
    # ── Step 1: Preprocess & Label ──
    print("\n[1/6] Loading and preprocessing SMS data...")
    df = load_and_preprocess(data_path)
    
    csv_path = os.path.join(data_dir, 'labeled_sms.csv')
    export_csv(df, csv_path)
    
    # ── Step 2: Visualize Label Distribution ──
    print("\n[2/6] Generating label distribution plots...")
    plot_label_distribution(df, results_dir)
    
    # ── Step 3: Train Classifier ──
    print("\n[3/6] Training ML classifier ensemble...")
    classifier = SmsClassifier()
    metrics = classifier.train(df, save=True)
    
    print(f"\n  ✓ Cross-validation accuracy: {metrics['cv_accuracy_mean']:.4f} "
          f"± {metrics['cv_accuracy_std']:.4f}")
    print(f"  ✓ Training accuracy:         {metrics['train_accuracy']:.4f}")
    print(f"  ✓ Weighted F1-score:         {metrics['f1_weighted']:.4f}")
    
    # ── Step 4: Plot Confusion Matrix ──
    print("\n[4/6] Generating confusion matrix...")
    plot_confusion_matrix(metrics, results_dir)
    
    # ── Step 5: Test Transaction Extraction ──
    print("\n[5/6] Testing transaction extraction...")
    test_extraction(df, results_dir)
    
    # ── Step 6: Test Spam Detection ──
    print("\n[6/6] Testing spam/fraud detection...")
    test_spam_detection(df, results_dir)
    
    # ── Summary ──
    print("\n" + "=" * 70)
    print("  Training Complete!")
    print("=" * 70)
    print(f"\n  ✓ Model saved to:          models/")
    print(f"  ✓ CSV exported to:         {csv_path}")
    print(f"  ✓ Visualizations saved to: {results_dir}/")
    print(f"\n  ✓ Accuracy: {metrics['cv_accuracy_mean']*100:.1f}%")
    print(f"  ✓ F1-Score: {metrics['f1_weighted']*100:.1f}%")
    
    # Print classification report
    print("\n── Classification Report ──")
    report = metrics['classification_report']
    for label in metrics['labels']:
        if label in report:
            r = report[label]
            print(f"  {label:25s}  P:{r['precision']:.3f}  R:{r['recall']:.3f}  "
                  f"F1:{r['f1-score']:.3f}  Support:{r['support']}")


def plot_label_distribution(df: pd.DataFrame, output_dir: str):
    """Plot distribution of labels and sub-labels."""
    fig, axes = plt.subplots(1, 2, figsize=(16, 6))
    
    # Label distribution
    label_counts = df['label'].value_counts()
    colors = sns.color_palette('viridis', len(label_counts))
    bars = axes[0].barh(label_counts.index, label_counts.values, color=colors)
    axes[0].set_title('SMS Classification Distribution', fontsize=14, fontweight='bold')
    axes[0].set_xlabel('Count')
    for bar, count in zip(bars, label_counts.values):
        axes[0].text(bar.get_width() + 5, bar.get_y() + bar.get_height()/2,
                     str(count), va='center', fontweight='bold')
    
    # Sub-label distribution
    sub_counts = df['sub_label'].value_counts().head(10)
    colors2 = sns.color_palette('rocket', len(sub_counts))
    bars2 = axes[1].barh(sub_counts.index, sub_counts.values, color=colors2)
    axes[1].set_title('Sub-Category Distribution (Top 10)', fontsize=14, fontweight='bold')
    axes[1].set_xlabel('Count')
    for bar, count in zip(bars2, sub_counts.values):
        axes[1].text(bar.get_width() + 2, bar.get_y() + bar.get_height()/2,
                     str(count), va='center', fontweight='bold')
    
    plt.tight_layout()
    path = os.path.join(output_dir, 'label_distribution.png')
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Saved: {path}")


def plot_confusion_matrix(metrics: dict, output_dir: str):
    """Plot confusion matrix heatmap."""
    cm = np.array(metrics['confusion_matrix'])
    labels = metrics['labels']
    
    fig, ax = plt.subplots(figsize=(10, 8))
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues',
                xticklabels=labels, yticklabels=labels, ax=ax)
    ax.set_title('Confusion Matrix — SMS Classification', fontsize=14, fontweight='bold')
    ax.set_ylabel('True Label')
    ax.set_xlabel('Predicted Label')
    plt.xticks(rotation=45, ha='right')
    plt.yticks(rotation=0)
    
    plt.tight_layout()
    path = os.path.join(output_dir, 'confusion_matrix.png')
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Saved: {path}")
    
    # Also plot normalized confusion matrix
    fig, ax = plt.subplots(figsize=(10, 8))
    cm_norm = cm.astype(float) / cm.sum(axis=1, keepdims=True)
    sns.heatmap(cm_norm, annot=True, fmt='.2%', cmap='YlOrRd',
                xticklabels=labels, yticklabels=labels, ax=ax)
    ax.set_title('Normalized Confusion Matrix (%)', fontsize=14, fontweight='bold')
    ax.set_ylabel('True Label')
    ax.set_xlabel('Predicted Label')
    plt.xticks(rotation=45, ha='right')
    plt.yticks(rotation=0)
    
    plt.tight_layout()
    path = os.path.join(output_dir, 'confusion_matrix_normalized.png')
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Saved: {path}")


def test_extraction(df: pd.DataFrame, output_dir: str):
    """Test transaction extraction on financial_transaction SMS."""
    txn_sms = df[df['label'] == 'financial_transaction']
    print(f"  Processing {len(txn_sms)} financial transaction SMS...")
    
    results = []
    extraction_success = 0
    
    for _, row in txn_sms.iterrows():
        sms = {
            '_id': row.get('sms_id', ''),
            'body': row.get('body', ''),
            'address': row.get('sender', ''),
            'date': row.get('timestamp', ''),
        }
        
        txn = extract_transaction(sms)
        results.append(txn)
        
        if txn.get('amount') is not None:
            extraction_success += 1
    
    success_rate = extraction_success / len(results) * 100 if results else 0
    print(f"  ✓ Amount extracted: {extraction_success}/{len(results)} ({success_rate:.1f}%)")
    
    # Save extraction results
    path = os.path.join(output_dir, 'extraction_results.json')
    with open(path, 'w') as f:
        json.dump(results, f, indent=2, default=str)
    print(f"  ✓ Saved: {path}")
    
    # Print some examples
    print("\n  ── Sample Extractions ──")
    for txn in results[:5]:
        print(f"  💰 {txn['transaction_type'] or '?':6s} Rs.{txn['amount'] or 0:>10,.2f} "
              f"| {txn['bank_name'] or '?':20s} | {txn['payment_method'] or '?':8s} "
              f"| {(txn['counterparty'] or '-')[:20]}")


def test_spam_detection(df: pd.DataFrame, output_dir: str):
    """Test spam detection across all SMS."""
    spam_count = 0
    spam_results = []
    
    for _, row in df.iterrows():
        sms = {
            'body': row.get('body', ''),
            'address': row.get('sender', ''),
        }
        result = detect_spam(sms)
        if result['is_spam']:
            spam_count += 1
            spam_results.append({
                'sender': sms['address'],
                'body': sms['body'][:100],
                **result,
            })
    
    print(f"  ✓ Detected {spam_count} spam/phishing SMS out of {len(df)}")
    
    if spam_results:
        path = os.path.join(output_dir, 'spam_detected.json')
        with open(path, 'w') as f:
            json.dump(spam_results, f, indent=2)
        print(f"  ✓ Saved: {path}")


if __name__ == '__main__':
    main()
