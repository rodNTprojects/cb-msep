#!/usr/bin/env bash
# gen_workload.sh — workload réaliste (P3) : un acte = un D -> un C -> une preuve.
# Produit workload/manifest.tsv, lu par plot_inference.py et analyze_inference.sh.
# COÛT : chaque preuve STARK prend un moment ; nombre d'items volontairement modeste.
# Usage : bash scripts/gen_workload.sh [spec.tsv]   (spec: key<TAB>D<TAB>min<TAB>max)
set -uo pipefail
cd "$(dirname "$0")/.."
HOST=zk/prover/target/release/host
OUT=workload; MAN="$OUT/manifest.tsv"; SPEC="${1:-}"

echo ">> build du host paramétré"
( cd zk/prover && cargo build --release --bin host ) >/dev/null 2>&1 || { echo "build host KO"; exit 1; }
mkdir -p "$OUT/receipts"
printf 'key\td\tmin\tmax\tC\tpublicin\treceipt\n' > "$MAN"

default_spec() { cat <<'EOF'
deed1	price=250000;parcel=AB-12;partyA=Alice;partyB=Bob	150000	300000
deed2	price=90000;parcel=XY-09;partyA=Ann;partyB=Bo	50000	100000
deed3	price=500000;parcel=ZZ-77;partyA=Cara;partyB=Dan	400000	600000
deed4	price=125500;parcel=KL-33;partyA=Eve;partyB=Fay	100000	150000
deed5	price=999999;parcel=QQ-01;partyA=Gil;partyB=Hal	750000	1000000
EOF
}
feed() { [ -n "$SPEC" ] && cat "$SPEC" || default_spec; }

n=0
while IFS=$'\t' read -r key d min max; do
  [ -z "${key:-}" ] && continue; case "$key" in \#*) continue;; esac
  n=$((n+1)); dir="$OUT/receipts/$key"; mkdir -p "$dir"
  echo ">> [$n] $key : min=$min max=$max (preuve en cours...)"
  RES=$(CBMSEP_D="$d" CBMSEP_MIN="$min" CBMSEP_MAX="$max" "$HOST" "$dir" 2>/dev/null) \
    || { echo "   preuve KO ($key)"; continue; }
  C=$(sed -n 's/^C=//p' <<<"$RES"); PUBIN=$(sed -n 's/^PUBLICIN=//p' <<<"$RES")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$d" "$min" "$max" "$C" "$PUBIN" "$dir/receipt.bin" >> "$MAN"
  echo "   C=$C  publicin=$PUBIN"
done < <(feed)
echo; echo "Manifeste : $MAN ($n items). Graphe : python3 scripts/plot_inference.py --domain 1000000"
