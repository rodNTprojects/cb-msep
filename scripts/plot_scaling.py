#!/usr/bin/env python3
"""P4 scaling figure from data/phase7_scaling_results.csv (test_phase7_scaling.sh).

Attestation latency as the non-member group grows (2..5), majority endorsement.
ZK-Only is a threshold baseline (t=1), not a point on this group-size sweep, so it
is not plotted here (see plot_overhead / the threshold discussion).

Usage: python3 scripts/plot_scaling.py [results.csv]
"""
import sys, os, csv
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _viz import apply, grid, label_points, BLUE
import matplotlib.pyplot as plt

def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "data/phase7_scaling_results.csv"
    if not os.path.exists(src):
        sys.exit(f"missing CSV: {src} (run test_phase7_scaling.sh)")
    rows = []
    with open(src) as f:
        for r in csv.DictReader(f):
            if r["label"].strip().lower().startswith("zk"):
                continue
            rows.append(dict(n=int(r["n"]), mean=float(r["mean_ms"])))
    rows.sort(key=lambda d: d["n"])
    apply(); os.makedirs("plots", exist_ok=True)

    fig, ax = plt.subplots(figsize=(6.4, 4.6))
    ns = [d["n"] for d in rows]; mus = [d["mean"] for d in rows]
    ax.plot(ns, mus, "o-", color=BLUE, lw=2, ms=8)
    label_points(ax, ns, mus, fmt="{:.0f} ms")
    ax.set_xlabel("Number of non-member organizations (majority endorsement)")
    ax.set_ylabel("Attestation latency (ms)")
    ax.set_xticks(ns)
    ax.set_ylim(0, max(mus) * 1.28)
    grid(ax); fig.tight_layout(); fig.savefig("plots/fig_scaling_latency.png", dpi=200)
    print("wrote plots/fig_scaling_latency.png")

if __name__ == "__main__":
    main()
