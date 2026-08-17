#!/usr/bin/env python3
"""Generate the evaluation figures as native-LaTeX PGF (.pgf) for \\input in the paper.

PGF is the LaTeX-native counterpart of the TikZ diagrams: the plot is drawn by
LaTeX at compile time, in the document's own font, fully vector. Run from the
project root (data/ and workload/manifest.tsv must exist):

    python3 scripts/make_pgf.py

Writes plots/*.pgf. In the paper:
    \\usepackage{pgf}
    \\input{plots/fig_overhead.pgf}
See README_pgf.md for the width caveat.
"""
import runpy, sys, os
import matplotlib
matplotlib.use("pgf")
import matplotlib.figure as mfig

matplotlib.rcParams.update({
    "pgf.texsystem": "pdflatex",   # or "lualatex" / "xelatex"
    "pgf.rcfonts": False,          # the LaTeX document chooses the fonts
    "text.usetex": False,
})

_orig = mfig.Figure.savefig
def _pgf(self, fname, *a, **k):
    if isinstance(fname, str) and fname.endswith(".png"):
        fname = fname[:-4] + ".pgf"
        k.pop("dpi", None); k["format"] = "pgf"
        matplotlib.rcParams["font.family"] = "serif"   # match a serif (IEEE) paper
    return _orig(self, fname, *a, **k)
mfig.Figure.savefig = _pgf

HERE = os.path.dirname(os.path.abspath(__file__))
JOBS = [
    ("plot_scaling.py", []),
    ("plot_inference.py", ["--domain", "1000000"]),
    ("plot_sizes.py", []),
    ("plot_overhead.py", []),
    ("plot_throughput.py", []),
]
for script, argv in JOBS:
    p = os.path.join(HERE, script)
    sys.argv = [p] + argv
    try:
        runpy.run_path(p, run_name="__main__")
    except SystemExit:
        pass
print("PGF written to plots/*.pgf")
