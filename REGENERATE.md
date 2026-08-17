# Phase 7 figures — regenerate everything locally

Extract over `~/cbmsep-net`. Prerequisite for plots: `pip install matplotlib`.

Every figure is a Python script (`scripts/plot_*.py`, shared style in
`scripts/_viz.py`) that reads a CSV/manifest and writes a PNG under `plots/`.
The measured CSVs are already included under `data/`, so you can redraw all
figures WITHOUT re-running the network:

```bash
python3 scripts/plot_scaling.py        # -> plots/fig_scaling_latency.png
python3 scripts/plot_inference.py --domain 1000000   # -> entropy + leak
python3 scripts/plot_sizes.py          # -> plots/fig_artifact_sizes.png
python3 scripts/plot_overhead.py       # -> plots/fig_overhead.png
python3 scripts/plot_throughput.py     # -> throughput + latency_concurrency
```

## Figure -> script -> data source

| Figure | Plot script | Data source |
|---|---|---|
| fig_scaling_latency | plot_scaling.py | data/phase7_scaling_results.csv |
| fig_inference_entropy | plot_inference.py | workload/manifest.tsv |
| fig_inference_leak | plot_inference.py | workload/manifest.tsv |
| fig_artifact_sizes | plot_sizes.py | receipt.bin (+ structural) |
| fig_overhead | plot_overhead.py | data/phase7_overhead_results.csv |
| fig_throughput | plot_throughput.py | data/phase7_throughput_results.csv |
| fig_latency_concurrency | plot_throughput.py | data/phase7_throughput_results.csv |

## Re-measure the data (optional, needs the running network)

To produce fresh CSVs instead of the bundled ones:

```bash
# scaling curve  -> data/phase7_scaling_results.csv
bash scripts/test_phase7_scaling.sh

# inference workload -> workload/manifest.tsv  (runs the prover per deed)
bash scripts/gen_workload.sh
bash scripts/analyze_inference.sh --domain 1000000     # A3 table (text)

# cost of obliviousness -> data/phase7_overhead_results.csv
bash scripts/deploy_datacc.sh            # once, if datacc not deployed
bash scripts/test_phase7.sh

# throughput/latency -> data/phase7_throughput_results.csv
REPS=10 bash scripts/test_phase7_throughput.sh
```

Then re-run the matching `plot_*.py`. All harnesses print progress live, use
per-run unique keys, and start with a preflight that fails loudly if a chaincode
is missing.

## Style

Colors and grid follow the TrustFabric look; the two series colors are `BLUE` and
`GOLD` at the top of `scripts/_viz.py` — change them there and every figure follows.
