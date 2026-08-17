"""Shared TrustFabric-style plotting for CB-MSEP Phase 7 figures.

Matches the reference paper look: blue + gold series, full light grid, thin box
frame, value labels on points/bars, simple legend. Import:
    from _viz import BLUE, GOLD, GRAY, apply, grid, label_points
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# TrustFabric palette
BLUE = "#4C9BD1"     # series 1 (e.g. Native)
GOLD = "#F5B301"     # series 2 (e.g. ZK-Only)
GREEN = "#1BAF7A"    # series 3 (e.g. Full CB-MSEP)
GRAY = "#7F7F7F"     # neutral 3rd series
INK  = "#222222"
GRIDC = "#d0d0d0"
FRAME = "#333333"

def apply():
    plt.rcParams.update({
        "font.family": "sans-serif",
        "font.sans-serif": ["DejaVu Sans", "Arial", "Helvetica"],
        "font.size": 12,
        "figure.facecolor": "white",
        "axes.facecolor": "white",
        "savefig.facecolor": "white",
        "axes.edgecolor": FRAME,
        "axes.linewidth": 0.8,
        "axes.labelcolor": INK,
        "text.color": INK,
        "xtick.color": INK, "ytick.color": INK,
        "axes.titlesize": 13,
    })

def grid(ax):
    ax.grid(True, color=GRIDC, linewidth=0.8)
    ax.set_axisbelow(True)
    for s in ax.spines.values():
        s.set_visible(True)

def label_points(ax, xs, ys, fmt="{:.1f}", dy=8, color=INK):
    for x, y in zip(xs, ys):
        ax.annotate(fmt.format(y), (x, y), textcoords="offset points",
                    xytext=(0, dy), ha="center", fontsize=10, color=color)
