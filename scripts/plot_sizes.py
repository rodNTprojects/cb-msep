#!/usr/bin/env python3
"""Artifact size figure (bytes, log), TrustFabric style.

Usage: python3 scripts/plot_sizes.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _viz import apply, grid, BLUE, INK
import matplotlib.pyplot as plt

def main():
    receipt = "chaincode/verification/testdata/receipt.bin"
    proof = os.path.getsize(receipt) if os.path.exists(receipt) else 221254
    items = [("STARK proof", proof), ("Binding sig", 1938),
             ("Commitment", 32), ("Image id", 32), ("Public input", 16)]
    items.sort(key=lambda x: x[1])
    apply(); os.makedirs("plots", exist_ok=True)
    fig, ax = plt.subplots(figsize=(6.4, 4.2))
    labels = [a for a, _ in items]; vals = [b for _, b in items]
    ax.barh(range(len(items)), vals, color=BLUE, height=0.6)
    ax.set_yticks(range(len(items))); ax.set_yticklabels(labels)
    ax.set_xscale("log")
    ax.set_xlabel("Size in bytes (log scale)")
    for i, v in enumerate(vals):
        ax.annotate(f"{v:,} B", (v, i), textcoords="offset points", xytext=(6, 0),
                    va="center", fontsize=10, color=INK)
    ax.set_xlim(8, proof * 3)
    grid(ax); fig.tight_layout(); fig.savefig("plots/fig_artifact_sizes.png", dpi=200)
    print("wrote plots/fig_artifact_sizes.png")

if __name__ == "__main__":
    main()
