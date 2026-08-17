# CB-MSEP — evaluation figures, native pgfplots

All Phase 7 evaluation figures redrawn as native LaTeX (pgfplots/TikZ). No
external image files: data is inlined, so the plots compile to vector graphics
at the document's own resolution. Same palette as the diagrams
(blue #4C9BD1, gold #F5B301, green #1BAF7A). No in-figure titles.

## Files

- `eval_figures_paper.tex` — the deliverable. Six figures as ready-to-drop
  `figure`/`figure*` environments with captions and `\label`s:
  scaling, on-chain overhead, throughput, latency-vs-concurrency, artifact
  sizes, and the two-panel inference figure. `\input` it or paste the blocks.
- `all_pgfplots.tex` — the five evaluation plots as a standalone document
  (one page each) for quick preview.
- `inference_pgfplots.tex` — the inference pair as a standalone groupplot.
- `inference_row_pgfplots.tex` — the inference pair as a `figure*` snippet.

## Preamble (add once to your document)

    \usepackage{pgfplots}
    \pgfplotsset{compat=1.18}
    \usepackage{subcaption}          % inference figure only
    \definecolor{cbblue}{HTML}{4C9BD1}
    \definecolor{cbgold}{HTML}{F5B301}
    \definecolor{cbgreen}{HTML}{1BAF7A}
    \pgfplotsset{cbaxis/.style={width=\linewidth, height=6cm,
       ymajorgrids, grid style={gray!25},
       tick label style={font=\small}, label style={font=\small}}}

## Notes

- `throughput` and `latency-concurrency` count only committed transactions;
  error bars are one standard deviation over repetitions.
- `overhead` and `sizes` use a log axis with explicit `[label]` strings, so the
  printed values are exact and never reformatted by the log tick style.
- Throughput/latency and inference are `figure*` (full width). To make them
  single-column, change to `figure` and set the axis `width` smaller.
- Preview: `pdflatex all_pgfplots.tex` then open `all_pgfplots.pdf`.
