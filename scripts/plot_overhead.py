#!/usr/bin/env python3
"""Cost-of-obliviousness figure from data/phase7_overhead_results.csv (test_phase7.sh).

Two bars: Native PDC vs Full CB-MSEP (proof + attestation), TrustFabric style.

Usage: python3 scripts/plot_overhead.py [results.csv]
"""
import sys, os, csv
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _viz import apply, grid, BLUE, GOLD, INK
import matplotlib.pyplot as plt

def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "data/phase7_overhead_results.csv"
    if not os.path.exists(src):
        sys.exit(f"missing CSV: {src} (run test_phase7.sh)")
    v = {r["label"]: float(r["mean_ms"]) for r in csv.DictReader(open(src))}
    native = v.get("TX1_NativePDC", 0.0)
    full = v.get("PRV", 0.0) + v.get("TX2_FullCBMSEP", 0.0)
    apply(); os.makedirs("plots", exist_ok=True)
    fig, ax = plt.subplots(figsize=(5.6, 4.6))
    bars = ax.bar([0, 1], [native, full], width=0.5, color=[BLUE, GOLD])
    for b in bars:
        ax.annotate(f"{b.get_height():.0f}", (b.get_x()+b.get_width()/2, b.get_height()),
                    textcoords="offset points", xytext=(0, 6), ha="center", fontsize=11, color=INK)
    ax.set_xticks([0, 1]); ax.set_xticklabels(["Native PDC", "Full CB-MSEP"])
    ax.set_ylabel("Latency (ms)")
    ax.set_ylim(0, full * 1.2 if full else 1)
    grid(ax); fig.tight_layout(); fig.savefig("plots/fig_overhead.png", dpi=200)
    print("wrote plots/fig_overhead.png")

if __name__ == "__main__":
    main()
