# CB-MSEP native-LaTeX figures (titles removed)

All in-figure titles are removed; the LaTeX \caption is the title.

figures_pgf/  the 7 figures as PGF  (\input, native LaTeX font, needs \usepackage{pgf})
figures_pdf/  same 7 as vector PDF   (\includegraphics, no LaTeX needed to include)
scripts/      plot_*.py + _viz.py + make_pgf.py (regenerate: python3 scripts/make_pgf.py, needs local latex)
diagrams_tikz/cbmsep_tikz.tex  architecture + sequence (TikZ)
inference_row.tex  the two inference figures as ONE horizontal block (subfigure)

Single figure:
  \begin{figure}[!t]\centering
    \resizebox{\columnwidth}{!}{\input{Figures/fig_overhead.pgf}}
    \caption{...}\label{fig:overhead}
  \end{figure}
