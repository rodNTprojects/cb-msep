#!/usr/bin/env python3
"""A3 inference figures from workload/manifest.tsv (gen_workload.sh), TrustFabric style.

k = max - min + 1  = number of values consistent with a true attestation
                     (the "revealed set" size). Residual entropy = log2(k) bits.

Fig A  residual entropy per predicate (bars); x labels show the interval.
Fig B  information leak vs k (line).

Usage: python3 scripts/plot_inference.py [manifest.tsv] [--domain N]
"""
import sys, os, csv, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _viz import apply, grid, BLUE, INK
import matplotlib.pyplot as plt

def kfmt(v):
    return f"{v/1000:.0f}k" if v >= 1000 else str(v)

def main():
    manifest = "workload/manifest.tsv"; domain = 1_000_000
    argv = sys.argv[1:]; i = 0
    while i < len(argv):
        if argv[i] == "--domain": domain = float(argv[i+1]); i += 2
        else: manifest = argv[i]; i += 1
    if not os.path.exists(manifest):
        sys.exit(f"missing manifest: {manifest} (run gen_workload.sh)")
    keys, mins, maxs, ks = [], [], [], []
    with open(manifest) as f:
        for r in csv.DictReader(f, delimiter="\t"):
            mn, mx = int(r["min"]), int(r["max"])
            if mx >= mn:
                keys.append(r["key"]); mins.append(mn); maxs.append(mx); ks.append(mx-mn+1)
    if not keys: sys.exit("empty manifest")
    res = [math.log2(k) for k in ks]
    apply(); os.makedirs("plots", exist_ok=True)

    # Fig A — residual entropy per predicate
    fig, ax = plt.subplots(figsize=(7.0, 4.8))
    bars = ax.bar(range(len(keys)), res, color=BLUE, width=0.6)
    for b, k in zip(bars, ks):
        ax.annotate(f"{b.get_height():.1f} bits", (b.get_x()+b.get_width()/2, b.get_height()),
                    textcoords="offset points", xytext=(0, 6), ha="center", fontsize=10, color=INK)
    xlabels = [f"[{kfmt(a)}, {kfmt(b)}]\nk = {kfmt(k)}" for a, b, k in zip(mins, maxs, ks)]
    ax.set_xticks(range(len(keys))); ax.set_xticklabels(xlabels, fontsize=9.5)
    ax.set_xlabel("Proved interval [min, max]   (k = max - min + 1 values)")
    ax.set_ylabel("Residual entropy, log2(k) (bits)")
    ax.set_ylim(0, max(res)+2.2)
    grid(ax); fig.tight_layout(); fig.savefig("plots/fig_inference_entropy.png", dpi=200)
    print("wrote plots/fig_inference_entropy.png")

    # Fig B — leak vs k
    order = sorted(range(len(ks)), key=lambda j: ks[j])
    kk = [ks[j] for j in order]; leak = [math.log2(domain) - res[j] for j in order]
    fig, ax = plt.subplots(figsize=(6.8, 4.8))
    ax.plot(kk, leak, "o-", color=BLUE, lw=2, ms=8)
    for k, l in zip(kk, leak):
        ax.annotate(f"{l:.1f}", (k, l), textcoords="offset points", xytext=(0, 8),
                    ha="center", fontsize=10, color=INK)
    ax.set_xscale("log")
    ax.set_xlabel("Revealed-set size  k = max - min + 1 (values)")
    ax.set_ylabel(f"Information leak (bits), domain N = {int(domain):,}")
    grid(ax); fig.tight_layout(); fig.savefig("plots/fig_inference_leak.png", dpi=200)
    print("wrote plots/fig_inference_leak.png")

if __name__ == "__main__":
    main()
