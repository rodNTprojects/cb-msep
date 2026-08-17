#!/usr/bin/env python3
"""Throughput/latency comparison from data/phase7_throughput_results.csv.

Multi-series (TrustFabric style): Native vs ZK-Only vs Full CB-MSEP on the same
axes. Columns: config, concurrency, tps_mean, tps_sd, lat_mean_ms, lat_sd_ms, reps.

Usage: python3 scripts/plot_throughput.py [results.csv]
"""
import sys, os, csv
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _viz import apply, grid, BLUE, GOLD, GREEN, INK
import matplotlib.pyplot as plt

STYLE = {"Native": (BLUE, "o"), "ZK-Only": (GOLD, "s"), "Full": (GREEN, "^")}

def load(src):
    series = {}
    with open(src) as f:
        for r in csv.DictReader(f):
            cfg = r["config"].strip()
            series.setdefault(cfg, []).append((
                int(r["concurrency"]), float(r["tps_mean"]), float(r.get("tps_sd", 0) or 0),
                float(r["lat_mean_ms"]), float(r.get("lat_sd_ms", 0) or 0)))
    for cfg in series: series[cfg].sort()
    return series

def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "data/phase7_throughput_results.csv"
    if not os.path.exists(src):
        sys.exit(f"missing CSV: {src} (run test_phase7_throughput.sh)")
    series = load(src)
    order = [c for c in STYLE if c in series] + [c for c in series if c not in STYLE]
    apply(); os.makedirs("plots", exist_ok=True)

    fig, ax = plt.subplots(figsize=(6.8, 4.6)); ymax = 0
    for cfg in order:
        col, mk = STYLE.get(cfg, (INK, "o"))
        C = [d[0] for d in series[cfg]]; y = [d[1] for d in series[cfg]]; e = [d[2] for d in series[cfg]]
        ax.errorbar(C, y, yerr=e, fmt=mk+"-", color=col, lw=2, ms=7, capsize=4, label=cfg)
        ymax = max(ymax, max(v+s for v, s in zip(y, e)))
    ax.set_xlabel("Number of concurrent clients"); ax.set_ylabel("Throughput (tx/s)")
    ax.set_xticks(sorted({d[0] for cfg in series for d in series[cfg]}))
    ax.set_ylim(0, ymax*1.2 if ymax else 1); ax.legend(frameon=False, fontsize=10)
    grid(ax); fig.tight_layout(); fig.savefig("plots/fig_throughput.png", dpi=200)
    print("wrote plots/fig_throughput.png")

    fig, ax = plt.subplots(figsize=(6.8, 4.6)); ymax = 0
    for cfg in order:
        col, mk = STYLE.get(cfg, (INK, "o"))
        C = [d[0] for d in series[cfg]]; y = [d[3] for d in series[cfg]]; e = [d[4] for d in series[cfg]]
        ax.errorbar(C, y, yerr=e, fmt=mk+"-", color=col, lw=2, ms=7, capsize=4, label=cfg)
        ymax = max(ymax, max(v+s for v, s in zip(y, e)))
    ax.set_xlabel("Number of concurrent clients"); ax.set_ylabel("Latency (ms)")
    ax.set_xticks(sorted({d[0] for cfg in series for d in series[cfg]}))
    ax.set_ylim(0, ymax*1.2 if ymax else 1); ax.legend(frameon=False, fontsize=10)
    grid(ax); fig.tight_layout(); fig.savefig("plots/fig_latency_concurrency.png", dpi=200)
    print("wrote plots/fig_latency_concurrency.png")

if __name__ == "__main__":
    main()
