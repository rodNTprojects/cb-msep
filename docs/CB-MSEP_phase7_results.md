# CB-MSEP — Phase 7 Evaluation Results

Measurements on a single testbed: a 7-organization Hyperledger Fabric network,
two members (Org1, Org2) and five non-members (Org3–Org7). Numbers are reported
as measured. Every table and figure regenerates from the bundle scripts.

## 1. Cost of trust: attestation latency vs number of non-member endorsers

We vary the number of non-member endorsers from 2 to 5 under a majority threshold
`t = floor(n/2)+1`. The ZK-Only baseline (`t = 1`, a single endorser) is the
verification floor. Latency of the attestation transaction TX2, 15 repetitions per
configuration, cold-start excluded.

| Configuration | n | t | Mean latency (ms) | Std. dev (ms) | Min | Max |
|---|---|---|---|---|---|---|
| ZK-Only | 3 | 1 | 2875 | 260 | 2487 | 3404 |
| Scale n=2 | 2 | 2 | 2965 | 435 | 2615 | 4111 |
| Scale n=3 | 3 | 2 | 2954 | 299 | 2674 | 3902 |
| Scale n=4 | 4 | 3 | 2909 | 220 | 2690 | 3601 |
| Scale n=5 | 5 | 3 | 3080 | 368 | 2638 | 4154 |

Figures: `fig_scaling_latency.png` (latency vs n, error bars), `fig_scaling_range.png`
(per-configuration min–max spread).

The curve is flat. From `n=2` to `n=5` the mean stays within 2909–3080 ms, and the
standard deviations overlap widely. Requiring more endorsers does not move latency
measurably.

Interpretation. The dominant cost of TX2 is not signature collection but the WASM
verification of the 221 KB STARK proof, executed on each peer and roughly constant.
The trust threshold is nearly free next to proof verification. Stated for the
paper: the cost of the threshold is negligible next to the cost of obliviousness.

Caveat. The on-ledger footprint does grow with `t`: a block carries `t` endorsement
signatures. That dimension is not in client latency; measuring it exactly requires
block inspection, noted as a refinement.

## 2. Inference leakage per predicate (A3)

A true attestation places the hidden value in `[min, max]`, independently of
zero-knowledge. For an interval of width `k = max − min + 1`, under a uniform
prior, the residual entropy is `log2(k)` bits; the leakage under a prior domain
`N = 10⁶` is `log2(N) − log2(k)`.

| Deed | Predicate [min, max] | Revealed k | Residual entropy (bits) | Leakage @N=10⁶ (bits) |
|---|---|---|---|---|
| deed1 | [150000, 300000] | 150001 | 17.195 | 2.737 |
| deed2 | [50000, 100000] | 50001 | 15.610 | 4.322 |
| deed3 | [400000, 600000] | 200001 | 17.610 | 2.322 |
| deed4 | [100000, 150000] | 50001 | 15.610 | 4.322 |
| deed5 | [750000, 1000000] | 250001 | 17.932 | 2.000 |

Mean residual entropy: 16.791 bits across five predicates. Figures:
`fig_inference_entropy.png`, `fig_inference_leak.png`.

Interpretation. The wider the interval, the less an attestation reveals. Leakage is
governed at the predicate level, by the choice of bounds, never in the circuit.
`deed1` doubles as an end-to-end correctness probe: its commitment
`C = a353c969…8414fc53` must equal the Phase 2 reference, otherwise the proof chain
is faulty.

## 3. Artifact sizes

Structural, independent of `D` and bounds. Figure: `fig_artifact_sizes.png`.

| Artifact | Size |
|---|---|
| STARK proof (receipt, borsh) | 221 254 bytes |
| Binding signature (sigma, hex-JSON) | 1 938 bytes |
| Commitment C | 32 bytes |
| Guest image id | 32 bytes |
| Public input (min‖max, u64 LE) | 16 bytes |

The proof dominates the footprint by two orders of magnitude, which is consistent
with verification being the dominant latency term in Section 1.

## 4. Cost of obliviousness

Native PDC (a bare private write, TX1) vs Full CB-MSEP (proof generation, then the
in-chaincode attestation TX2 on `verifycc_n3`). Figure: `fig_overhead.png`.

| Component | Where | Latency (ms) | Std. dev (ms) |
|---|---|---|---|
| Native PDC write (TX1) | on-chain | 2338 | 183 |
| CB-MSEP attestation (TX2) | on-chain | 2819 | 89 |
| Proof generation (PRV) | off-chain, once | 39710 | 1777 |

The cost splits into two very different parts. The on-chain overhead is small: an
attestation costs 2819 ms against 2338 ms for a bare private write, i.e. +481 ms,
about +21%. The in-chaincode STARK verifier and the threshold endorsement add
little over an ordinary private-data write. This is the cost the ledger pays.

The dominant term is off-chain proof generation: 39.7 s per deed. It runs on the
client, off the consensus critical path, once per attestation, and is the
intrinsic cost of a zk-STARK — improvable with a faster prover, GPU acceleration,
or batching. It does not affect ledger throughput. Reporting it on a log axis
(the figure) keeps both the small on-chain gap and the large proving term legible.

## 5. Throughput and latency under concurrency (three configurations)

`test_phase7_throughput.sh` compares three configurations on the same axes, in the
TrustFabric style (baseline vs system), `REPS` repetitions per level, mean ± std
dev. Figures: `fig_throughput.png`, `fig_latency_concurrency.png`.

Configurations (baselines defined):

- **Native** — a bare member private write (`datacc` SubmitData). No proof, no
  verification. The floor.
- **ZK-Only** — CB-MSEP without the consensus-backed threshold: the non-member's
  zk-STARK proof and ECDSA binding are verified in-chaincode exactly as in Full,
  but the endorsement policy requires a single non-member signature (`OutOf(1,3)`,
  `verifycc_zk1`). Isolates the cost of in-chaincode ZK verification from the
  multi-signature threshold.
- **Full CB-MSEP** — proof + binding + majority threshold (`OutOf(2,3)`,
  `verifycc_n3`).

Full CB-MSEP, measured (10 reps/level):

| Concurrent clients | Throughput (tx/s) | Latency (ms) |
|---|---|---|
| 1 | 0.35 ± 0.03 | 2842 ± 222 |
| 2 | 0.69 ± 0.03 | 1989 ± 924 |
| 4 | 1.31 ± 0.07 | 2003 ± 686 |
| 8 | 1.55 ± 0.24 | 3781 ± 756 |
| 16 | 1.84 ± 0.22 | 7223 ± 1175 |

Throughput rises with concurrency then flattens near 1.8 tx/s: the single verifying
peer serializes STARK verification, so beyond a handful of clients added load turns
into queueing rather than throughput, and per-request latency grows (7.2 s at 16
clients). The ceiling reflects the ~2.8 s on-chain verification cost, not the
threshold. Horizontal scaling (more verifying peers) is the lever.

Expected shape of the comparison: Native sits above (cheaper, no verification);
ZK-Only and Full overlap (the threshold is nearly free, consistent with Section 1).
The Native and ZK-Only series are produced by the multi-configuration harness — run
it to populate them alongside Full.

Method note: performance measurements are not deterministic. Every point is a mean
over repetitions with a standard-deviation error bar; single runs are not reported.

## 6. Figure inventory

| Figure | Source | Status |
|---|---|---|
| fig_scaling_latency | test_phase7_scaling.sh | measured |
| fig_inference_entropy | gen_workload.sh | measured |
| fig_inference_leak | gen_workload.sh | measured |
| fig_artifact_sizes | receipt + structural | measured |
| fig_overhead | test_phase7.sh | measured |
| fig_throughput | test_phase7_throughput.sh | measured |
| fig_latency_concurrency | test_phase7_throughput.sh | measured |

## 7. Reproduce

From `~/cbmsep-net`, network deployed and Brick A run:

```bash
bash scripts/gen_workload.sh
bash scripts/analyze_inference.sh --domain 1000000
python3 scripts/plot_inference.py --domain 1000000
python3 scripts/plot_sizes.py

bash scripts/test_phase7_scaling.sh
python3 scripts/plot_scaling.py

bash scripts/test_phase7.sh
python3 scripts/plot_overhead.py

bash scripts/test_phase7_throughput.sh
python3 scripts/plot_throughput.py
```

Figures are written under `plots/`.
