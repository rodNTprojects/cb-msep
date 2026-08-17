# CB-MSEP

A protocol that lets organizations outside a Hyperledger Fabric private data
collection endorse a transaction by verifying a zero-knowledge proof, without
access to the data, without trusted hardware, and on unmodified Fabric.

This guide takes you from an empty machine to a working network, a single
attestation, a verification of the central property, and the measurements
reported in the accompanying paper. Each stage stands on its own: stop after
stage 3 if all you want is to see the scheme work.

> **Open point.** The base deployment brings up five organizations: Org1 and Org2
> hold the collection, Org3 to Org5 attest under `OutOf(2,3)`. The paper
> describes a seven-organization network, which is the scaling bench obtained
> with `deploy_scaling.sh`. Reconcile the two before publishing this file.

---

## Stage 0 — Prerequisites

| Component | Version | Check |
|---|---|---|
| Hyperledger Fabric | 2.5.x binaries and images | `peer version` |
| Docker Engine | 24+, Compose v2 | `docker compose version` |
| Go | 1.22 | `go version` |
| Rust | stable, plus `wasm32-wasip1` | `rustup target list --installed` |
| RISC Zero zkVM | 3.0.6 | `cargo risczero --version` |
| Python | 3.10+ | figures and inference analysis only |

```bash
git clone <REPO_URL> cbmsep-net && cd cbmsep-net
```

Reference host for the reported numbers: Intel Core i7-8650U, 4 cores, 16 GB,
Ubuntu 22.04 under WSL2. Absolute latency and throughput depend on it.

`scripts/env.sh` is never run on its own. Every other script sources it for
`setGlobals`, the orderer flags and the CA paths.

---

## Stage 1 — Bring the network up

Five steps, in this order. Two of them produce artifacts that `CC_V` embeds at
package time, so they cannot be deferred.

```bash
# 1. Compile the STARK verifier to WebAssembly
bash scripts/build_verifier.sh          # -> chaincode/verification/verifier.wasm

# 2. Start the network: cryptogen, genesis block, containers, orderer join
bash scripts/up.sh

# 3. Produce the reference receipt and the guest image identifier
( cd zk/prover && cargo run --release --bin host )
                                        # -> chaincode/verification/testdata/

# 4. Collect the member CA roots and pin the expected image id into CC_V
bash scripts/refresh_binding_material.sh

# 5. Peers join the channel
bash scripts/channel.sh
```

Step 4 depends on both step 2, for the cryptogen roots, and step 3, for the image
identifier. Step 1 is independent of the network and can run at any point before
deployment.

```bash
docker ps --format '{{.Names}}'
```

Then deploy both chaincodes:

```bash
bash scripts/deploy.sh
```

This packages and commits `datacc` under `OR(Org1MSP.member, Org2MSP.member)` and
`verifycc` under `OutOf(2, Org3MSP, Org4MSP, Org5MSP)`. The lifecycle majority is
reached by having a non-member approve the `datacc` definition and a member
approve the `verifycc` definition, without installing either.

`deploy_datacc.sh` and `deploy_scaling.sh` are **not** part of bringing the
network up. They serve the scaling bench of stage 5.

---

## Stage 2 — One attestation, end to end

Five commands. This is the shortest path to seeing the scheme work.

```bash
# 1. Write the deed. TX1 puts D in the collection, records C = sha256(D)
#    in public state, and sets the status to pending.
bash scripts/submit.sh asset1

# 2. Produce the proof, if D has changed since stage 1.
( cd zk/prover && cargo run --release --bin host )
```

`submit.sh` covers TX1 only. The attestation is assembled by chaining the two
clients; `test_phase7.sh` automates what follows.

```bash
# 3. Collect the member co-signatures over (key, C). This is sigma.
cd client/sign_binding
go run . asset1 <Chex> \
  Org1MSP=organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp \
  Org2MSP=organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp \
  > /tmp/sigma.hex
cd ../..

# 4. Submit TX2 from a non-member. The client targets Org3 by default.
cd client/attest
go run . --chaincode verifycc --key asset1 \
  --commitment <Chex> \
  --publicin <publicinHex> \
  --receipt chaincode/verification/testdata/receipt.bin \
  --sigma /tmp/sigma.hex
cd ../..

# 5. Confirm the commit: the status leaves pending.
setGlobals 1 && peer chaincode query -C cbmsep -n datacc \
  -c '{"function":"ReadRecord","Args":["asset1"]}'
```

`<Chex>` and `<publicinHex>` for each deed are in `workload/manifest.tsv`, columns
`C` and `publicin`. For the reference deed, `C = a353c969…8414fc53` and
`publicin = f049020000000000e093040000000000`, which encodes min = 150000 and
max = 300000 as little-endian u64.

At this point a non-member organization has endorsed a claim about data it never
received.

---

## Stage 3 — Verify the claim

The paper's central property is that the attesting chaincode cannot read the
private data. The check is static, and that is deliberate.

```bash
bash scripts/check_obliviousness.sh
```

It enumerates the ten private-data methods of the Go shim, reads and writes
alike, and verifies that none is called in the deployed sources of `CC_V`,
excluding `vendor/` and `*_test.go`. The verdict is machine-readable:

```
obliviousness_ok=1 apis_checked=10 violations=0
```

Exit code 0 on success, 1 on violation.

**Why static rather than observational.** A taint analysis follows a path from
source to sink. With no private-read source at all, the set of tainted paths is
empty and the property holds vacuously. The absence of a call is a sufficient
condition, decidable by exhaustive enumeration over a finite API. The script
therefore shows that `CC_V` *cannot* read the data, which is stronger than an
observation showing that at one moment it *has not*.

If you also want the runtime picture, the private-value database is absent from a
non-member's CouchDB:

```bash
curl -s http://admin:adminpw@localhost:7984/_all_dbs | tr ',' '\n' | grep datacc
```

On Org3 you see the public database and the hash database `$$hassetpdc`, but not
`$$passetpdc`, which exists only on Org1 and Org2, at ports 5984 and 6984.

---

## Stage 4 — Functional and security tests

```bash
bash scripts/test_phase5.sh   # 8 functional: happy path, precondition,
                              # idempotence, cancel guard, MVCC concurrency
bash scripts/test_phase6.sh   # 6 security, mapped to Table II of the paper
```

---

## Stage 5 — Reproduce the reported measurements

Generate the workload first. The script compiles the host once, then runs it per
deed, filling `workload/receipts/<key>/receipt.bin` and `workload/manifest.tsv`.

```bash
bash scripts/gen_workload.sh
```

Five synthetic deeds by default, with proved intervals in thousands: `[150,300]`,
`[50,100]`, `[400,600]`, `[100,150]`, `[750,1000]`. Widths are varied on purpose
so that the effect of predicate granularity on leakage is visible. Pass a
`spec.tsv` with columns `key`, `D`, `min`, `max` for a different set. Proving
takes about 40 s per deed on the reference host, which dominates setup time.

Then the three campaigns. Run each on a freshly started network.

```bash
bash scripts/test_phase7.sh             # overhead: TX1, TX2, proving, 15 reps
bash scripts/test_phase7_scaling.sh     # groups of 2 to 5 non-members
bash scripts/test_phase7_throughput.sh  # 1, 2, 4, 8, 16 clients, 5 reps each
```

The scaling campaign needs the seven-organization bench:

```bash
bash scripts/deploy_scaling.sh          # verifycc_n2 .. verifycc_n5
bash scripts/deploy_datacc.sh
```

Two points that decide whether the numbers are meaningful:

- **Unique keys.** Every run, configuration, concurrency level and repetition
  must use a distinct ledger key. Reusing an attested key makes `CC_V` reject the
  transaction through its idempotence guard, which appears as a spurious 50 %
  failure rate rather than as an error. The scripts derive keys from the tuple.
- **Repetitions.** Latency is not deterministic on a live network. Every reported
  value is a mean with its standard deviation, never a single run.

Results land in `data/`:

```
data/phase7_overhead_results.csv
data/phase7_scaling_results.csv
data/phase7_throughput_results.csv
```

Expected wall-clock time on the reference host: roughly 20 minutes for overhead,
15 for scaling, 45 for throughput, excluding proof generation.

---

## Stage 6 — Regenerate the reported values

```bash
python3 scripts/plot_overhead.py
python3 scripts/plot_scaling.py
python3 scripts/plot_throughput.py
python3 scripts/plot_sizes.py
bash    scripts/analyze_inference.sh && python3 scripts/plot_inference.py
```

Each script reads the corresponding CSV and prints the means and standard
deviations quoted in the paper, alongside the plot it produces.

The figures in the paper are TikZ, with coordinates written directly in the
LaTeX source. Update them by replacing the coordinate lists with these values.

**Derived quantities, no network needed.** Residual entropy per predicate is
`log2(k)` with `k = max - min + 1`. The corresponding leak is `log2(N/k)` with
`N = 10^6`, an upper bound on the prices the workload covers, taken uniform.

---

## Known deviations

- Throughput saturates near 1.8 tx/s. Two causes are plausible, a single
  verifying peer and contention among all organizations on four cores, and we did
  not separate them. Expect different numbers on a larger host, or with `CC_V`
  replicated across non-members.
- Standard deviations grow at 8 and 16 concurrent clients. This is queueing
  jitter.
- Proof generation varies by a few seconds between runs on the same input.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| Every attestation rejected | guest image id out of date; rerun the prover, then `refresh_binding_material.sh`, then redeploy `CC_V` |
| Binding verification fails | member CA roots not refreshed after regenerating crypto material |
| `verifier.wasm` missing at package time | `build_verifier.sh` not run before `deploy.sh` |
| Roughly half the transactions fail | key collision across repetitions; see stage 5 |
| MVCC conflicts under concurrency | expected; the harness retries and counts committed transactions only |
| `CC_V` cannot find the commitment | TX1 has not committed; the attestation requires the pending state |