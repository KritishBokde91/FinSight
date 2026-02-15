"""
train.py — End-to-End Training & Visualization Script
======================================================
Runs the full pipeline: preprocess → label → train → evaluate → visualize.
Generates confusion matrix, ROC curves, feature importance, loss curves,
precision-recall curves, and label distribution.

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
from sklearn.metrics import (
    confusion_matrix, roc_curve, auc,
    precision_recall_curve, average_precision_score,
)
from sklearn.preprocessing import label_binarize

# Add parent dir to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pipeline.preprocessor import load_and_preprocess, export_csv
from pipeline.classifier import SmsClassifier
from pipeline.extractor import extract_transaction
from pipeline.fraud_detector import detect_spam


# ─── Plotting Style ──────────────────────────────────────────────────────
plt.rcParams.update({
    'figure.facecolor': '#0d1117',
    'axes.facecolor': '#161b22',
    'axes.edgecolor': '#30363d',
    'axes.labelcolor': '#c9d1d9',
    'text.color': '#c9d1d9',
    'xtick.color': '#8b949e',
    'ytick.color': '#8b949e',
    'grid.color': '#21262d',
    'grid.alpha': 0.6,
    'font.family': 'sans-serif',
    'font.size': 11,
})

COLORS = ['#58a6ff', '#3fb950', '#f0883e', '#f778ba', '#bc8cff',
          '#79c0ff', '#56d364', '#e3b341', '#ff7b72', '#d2a8ff']


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
    print("\n[1/9] Loading and preprocessing SMS data...")
    df = load_and_preprocess(data_path)
    
    csv_path = os.path.join(data_dir, 'labeled_sms.csv')
    export_csv(df, csv_path)
    
    # ── Step 2: Visualize Label Distribution ──
    print("\n[2/9] Generating label distribution plots...")
    plot_label_distribution(df, results_dir)
    
    # ── Step 3: Train Classifier ──
    print("\n[3/9] Training ML classifier ensemble...")
    classifier = SmsClassifier()
    metrics = classifier.train(df, save=True)
    
    print(f"\n  ✓ Cross-validation accuracy: {metrics['cv_accuracy_mean']:.4f} "
          f"± {metrics['cv_accuracy_std']:.4f}")
    print(f"  ✓ Training accuracy:         {metrics['train_accuracy']:.4f}")
    print(f"  ✓ Weighted F1-score:         {metrics['f1_weighted']:.4f}")
    
    # ── Step 4: Plot Confusion Matrix ──
    print("\n[4/9] Generating confusion matrix...")
    plot_confusion_matrix(metrics, results_dir)
    
    # ── Step 5: XGBoost Loss Curves ──
    print("\n[5/9] Generating XGBoost training loss curves...")
    plot_xgb_loss_curves(metrics, results_dir)
    
    # ── Step 6: Learning Rate Schedule ──
    print("\n[6/9] Generating learning rate schedule...")
    plot_learning_rate(metrics, results_dir)
    
    # ── Step 7: Feature Importance ──
    print("\n[7/9] Generating feature importance plot...")
    plot_feature_importance(metrics, results_dir)
    
    # ── Step 8: ROC & PR Curves ──
    print("\n[8/9] Generating ROC and Precision-Recall curves...")
    plot_roc_curves(metrics, results_dir)
    plot_pr_curves(metrics, results_dir)
    
    # ── Step 9: Test Extraction & Spam Detection ──
    print("\n[9/9] Testing transaction extraction & spam detection...")
    test_extraction(df, results_dir)
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
    
    # Print visualization list
    print("\n── Generated Visualizations ──")
    for f in sorted(os.listdir(results_dir)):
        if f.endswith('.png'):
            print(f"  📊 {f}")


# ═══════════════════════════════════════════════════════════════════════
# VISUALIZATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════

def plot_label_distribution(df: pd.DataFrame, output_dir: str):
    """Plot distribution of labels and sub-labels."""
    fig, axes = plt.subplots(1, 2, figsize=(18, 7))
    
    # Label distribution
    label_counts = df['label'].value_counts()
    bars = axes[0].barh(label_counts.index, label_counts.values,
                        color=COLORS[:len(label_counts)], edgecolor='none', height=0.6)
    axes[0].set_title('SMS Classification Distribution', fontsize=15, fontweight='bold', pad=15)
    axes[0].set_xlabel('Count', fontsize=12)
    axes[0].grid(axis='x', alpha=0.3)
    for bar, count in zip(bars, label_counts.values):
        pct = count / len(df) * 100
        axes[0].text(bar.get_width() + 8, bar.get_y() + bar.get_height()/2,
                     f'{count} ({pct:.1f}%)', va='center', fontweight='bold', fontsize=10)
    
    # Sub-label distribution
    sub_counts = df['sub_label'].value_counts().head(10)
    bars2 = axes[1].barh(sub_counts.index, sub_counts.values,
                         color=COLORS[:len(sub_counts)], edgecolor='none', height=0.6)
    axes[1].set_title('Sub-Category Distribution (Top 10)', fontsize=15, fontweight='bold', pad=15)
    axes[1].set_xlabel('Count', fontsize=12)
    axes[1].grid(axis='x', alpha=0.3)
    for bar, count in zip(bars2, sub_counts.values):
        axes[1].text(bar.get_width() + 3, bar.get_y() + bar.get_height()/2,
                     str(count), va='center', fontweight='bold', fontsize=10)
    
    plt.tight_layout(pad=3)
    path = os.path.join(output_dir, 'label_distribution.png')
    plt.savefig(path, dpi=200, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Saved: {path}")


def plot_confusion_matrix(metrics: dict, output_dir: str):
    """Plot confusion matrix heatmaps (raw + normalized)."""
    cm = np.array(metrics['confusion_matrix'])
    labels = metrics['labels']
    
    fig, axes = plt.subplots(1, 2, figsize=(20, 8))
    
    # Raw counts
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues',
                xticklabels=labels, yticklabels=labels, ax=axes[0],
                linewidths=0.5, linecolor='#30363d',
                cbar_kws={'shrink': 0.8})
    axes[0].set_title('Confusion Matrix (Counts)', fontsize=14, fontweight='bold', pad=15)
    axes[0].set_ylabel('True Label', fontsize=12)
    axes[0].set_xlabel('Predicted Label', fontsize=12)
    axes[0].tick_params(axis='x', rotation=45)
    
    # Normalized
    cm_norm = cm.astype(float) / cm.sum(axis=1, keepdims=True)
    sns.heatmap(cm_norm, annot=True, fmt='.2%', cmap='YlOrRd',
                xticklabels=labels, yticklabels=labels, ax=axes[1],
                linewidths=0.5, linecolor='#30363d',
                cbar_kws={'shrink': 0.8})
    axes[1].set_title('Confusion Matrix (Normalized %)', fontsize=14, fontweight='bold', pad=15)
    axes[1].set_ylabel('True Label', fontsize=12)
    axes[1].set_xlabel('Predicted Label', fontsize=12)
    axes[1].tick_params(axis='x', rotation=45)
    
    plt.tight_layout(pad=3)
    path = os.path.join(output_dir, 'confusion_matrix.png')
    plt.savefig(path, dpi=200, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Saved: {path}")


def plot_xgb_loss_curves(metrics: dict, output_dir: str):
    """Plot XGBoost training & validation loss per iteration (epoch)."""
    eval_results = metrics.get('xgb_eval_results')
    if not eval_results:
        print("  ⚠ No XGBoost eval results available, skipping.")
        return
    
    fig, ax = plt.subplots(figsize=(12, 6))
    
    # Get loss data
    train_loss = eval_results['validation_0']['mlogloss']
    val_loss = eval_results['validation_1']['mlogloss']
    epochs = range(1, len(train_loss) + 1)
    
    ax.plot(epochs, train_loss, color=COLORS[0], linewidth=2,
            label='Training Loss', alpha=0.9)
    ax.plot(epochs, val_loss, color=COLORS[2], linewidth=2,
            label='Validation Loss', alpha=0.9)
    
    # Find best epoch
    best_epoch = np.argmin(val_loss) + 1
    best_loss = min(val_loss)
    ax.axvline(x=best_epoch, color=COLORS[3], linestyle='--', alpha=0.7,
               label=f'Best Epoch ({best_epoch})')
    ax.scatter([best_epoch], [best_loss], color=COLORS[3], s=100, zorder=5, marker='*')
    
    ax.set_xlabel('Iteration (Epoch)', fontsize=13)
    ax.set_ylabel('Multi-class Log Loss', fontsize=13)
    ax.set_title('XGBoost Training & Validation Loss', fontsize=15, fontweight='bold', pad=15)
    ax.legend(fontsize=11, framealpha=0.8, facecolor='#161b22', edgecolor='#30363d')
    ax.grid(True, alpha=0.3)
    
    # Add text annotation
    ax.text(0.97, 0.95, f'Final Train Loss: {train_loss[-1]:.6f}\n'
            f'Final Val Loss: {val_loss[-1]:.6f}\n'
            f'Best Val Loss: {best_loss:.6f} (epoch {best_epoch})',
            transform=ax.transAxes, fontsize=10, va='top', ha='right',
            bbox=dict(boxstyle='round,pad=0.5', facecolor='#21262d', edgecolor='#30363d'))
    
    plt.tight_layout(pad=2)
    path = os.path.join(output_dir, 'xgb_loss_curves.png')
    plt.savefig(path, dpi=200, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Saved: {path}")


def plot_learning_rate(metrics: dict, output_dir: str):
    """Plot learning rate schedule and convergence analysis."""
    eval_results = metrics.get('xgb_eval_results')
    if not eval_results:
        print("  ⚠ No eval results available, skipping.")
        return
    
    base_lr = metrics.get('xgb_learning_rate', 0.1)
    n_estimators = metrics.get('xgb_n_estimators', 200)
    val_loss = eval_results['validation_1']['mlogloss']
    
    fig, axes = plt.subplots(1, 2, figsize=(16, 6))
    
    # Left: Effective learning contribution per round
    epochs = range(1, n_estimators + 1)
    # XGBoost uses constant lr by default, but we show effective contribution
    lr_schedule = [base_lr] * n_estimators
    axes[0].plot(epochs, lr_schedule, color=COLORS[0], linewidth=2.5, label=f'Learning Rate = {base_lr}')
    axes[0].fill_between(epochs, 0, lr_schedule, alpha=0.15, color=COLORS[0])
    axes[0].set_xlabel('Iteration', fontsize=12)
    axes[0].set_ylabel('Learning Rate', fontsize=12)
    axes[0].set_title('Learning Rate Schedule', fontsize=14, fontweight='bold', pad=15)
    axes[0].set_ylim(0, base_lr * 1.5)
    axes[0].legend(fontsize=11, framealpha=0.8, facecolor='#161b22', edgecolor='#30363d')
    axes[0].grid(True, alpha=0.3)
    
    # Right: Loss improvement rate per epoch
    loss_deltas = [0] + [val_loss[i-1] - val_loss[i] for i in range(1, len(val_loss))]
    colors_delta = [COLORS[1] if d >= 0 else COLORS[4] for d in loss_deltas]
    axes[1].bar(epochs, loss_deltas, color=colors_delta, alpha=0.7, width=1.0)
    axes[1].axhline(y=0, color='#8b949e', linewidth=0.8)
    axes[1].set_xlabel('Iteration', fontsize=12)
    axes[1].set_ylabel('Loss Improvement (Δ)', fontsize=12)
    axes[1].set_title('Per-Iteration Loss Improvement', fontsize=14, fontweight='bold', pad=15)
    axes[1].grid(True, alpha=0.3)
    
    plt.tight_layout(pad=3)
    path = os.path.join(output_dir, 'learning_rate_schedule.png')
    plt.savefig(path, dpi=200, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Saved: {path}")


def plot_feature_importance(metrics: dict, output_dir: str):
    """Plot top 30 most important features from XGBoost."""
    names = metrics.get('feature_names', [])
    importances = metrics.get('feature_importance', [])
    
    if not names or not importances:
        print("  ⚠ No feature importance data, skipping.")
        return
    
    # Sort and take top 30
    pairs = sorted(zip(names, importances), key=lambda x: x[1], reverse=True)[:30]
    top_names = [p[0] for p in pairs][::-1]
    top_values = [p[1] for p in pairs][::-1]
    
    fig, ax = plt.subplots(figsize=(14, 10))
    bars = ax.barh(range(len(top_names)), top_values,
                   color=COLORS[0], edgecolor='none', height=0.7, alpha=0.85)
    
    ax.set_yticks(range(len(top_names)))
    ax.set_yticklabels(top_names, fontsize=9)
    ax.set_xlabel('Feature Importance (Gain)', fontsize=12)
    ax.set_title('Top 30 Features — XGBoost Importance', fontsize=15, fontweight='bold', pad=15)
    ax.grid(axis='x', alpha=0.3)
    
    # Annotate top 5
    for i, (bar, val) in enumerate(zip(bars[-5:], top_values[-5:])):
        ax.text(bar.get_width() + 0.001, bar.get_y() + bar.get_height()/2,
                f'{val:.4f}', va='center', fontsize=9, fontweight='bold', color=COLORS[2])
    
    plt.tight_layout(pad=2)
    path = os.path.join(output_dir, 'feature_importance.png')
    plt.savefig(path, dpi=200, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Saved: {path}")


def plot_roc_curves(metrics: dict, output_dir: str):
    """Plot One-vs-Rest ROC curves for each class."""
    y_true = np.array(metrics.get('y_true', []))
    y_proba = np.array(metrics.get('y_proba', []))
    labels = metrics.get('labels', [])
    
    if len(y_true) == 0 or len(y_proba) == 0:
        print("  ⚠ No probability data, skipping ROC curves.")
        return
    
    n_classes = len(labels)
    y_bin = label_binarize(y_true, classes=range(n_classes))
    
    fig, ax = plt.subplots(figsize=(10, 8))
    
    for i, label in enumerate(labels):
        fpr, tpr, _ = roc_curve(y_bin[:, i], y_proba[:, i])
        roc_auc = auc(fpr, tpr)
        ax.plot(fpr, tpr, color=COLORS[i % len(COLORS)], linewidth=2,
                label=f'{label} (AUC = {roc_auc:.4f})', alpha=0.85)
    
    ax.plot([0, 1], [0, 1], color='#484f58', linestyle='--', linewidth=1, label='Random (AUC = 0.5)')
    ax.set_xlabel('False Positive Rate', fontsize=13)
    ax.set_ylabel('True Positive Rate', fontsize=13)
    ax.set_title('ROC Curves — One-vs-Rest', fontsize=15, fontweight='bold', pad=15)
    ax.legend(loc='lower right', fontsize=10, framealpha=0.8,
              facecolor='#161b22', edgecolor='#30363d')
    ax.grid(True, alpha=0.3)
    ax.set_xlim([-0.02, 1.02])
    ax.set_ylim([-0.02, 1.02])
    
    plt.tight_layout(pad=2)
    path = os.path.join(output_dir, 'roc_curves.png')
    plt.savefig(path, dpi=200, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Saved: {path}")


def plot_pr_curves(metrics: dict, output_dir: str):
    """Plot Precision-Recall curves for each class."""
    y_true = np.array(metrics.get('y_true', []))
    y_proba = np.array(metrics.get('y_proba', []))
    labels = metrics.get('labels', [])
    
    if len(y_true) == 0 or len(y_proba) == 0:
        print("  ⚠ No probability data, skipping PR curves.")
        return
    
    n_classes = len(labels)
    y_bin = label_binarize(y_true, classes=range(n_classes))
    
    fig, ax = plt.subplots(figsize=(10, 8))
    
    for i, label in enumerate(labels):
        precision, recall, _ = precision_recall_curve(y_bin[:, i], y_proba[:, i])
        ap = average_precision_score(y_bin[:, i], y_proba[:, i])
        ax.plot(recall, precision, color=COLORS[i % len(COLORS)], linewidth=2,
                label=f'{label} (AP = {ap:.4f})', alpha=0.85)
    
    ax.set_xlabel('Recall', fontsize=13)
    ax.set_ylabel('Precision', fontsize=13)
    ax.set_title('Precision-Recall Curves', fontsize=15, fontweight='bold', pad=15)
    ax.legend(loc='lower left', fontsize=10, framealpha=0.8,
              facecolor='#161b22', edgecolor='#30363d')
    ax.grid(True, alpha=0.3)
    ax.set_xlim([-0.02, 1.02])
    ax.set_ylim([-0.02, 1.05])
    
    plt.tight_layout(pad=2)
    path = os.path.join(output_dir, 'precision_recall_curves.png')
    plt.savefig(path, dpi=200, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Saved: {path}")


# ═══════════════════════════════════════════════════════════════════════
# TEST FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════

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
