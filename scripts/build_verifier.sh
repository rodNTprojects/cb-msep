#!/usr/bin/env bash
# Construit le module WASM de la brique B et le dépose dans le package CC_V.
# À lancer depuis la racine cbmsep-net.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/zk/verifier-wasm"
DST="$ROOT/chaincode/verification"

echo ">> Build du vérifieur WASM (zk/verifier-wasm)"
rustup target add wasm32-wasip1 >/dev/null 2>&1 || true
( cd "$SRC" && cargo build --release --target wasm32-wasip1 )

cp "$SRC/target/wasm32-wasip1/release/verifier_wasm.wasm" "$DST/verifier.wasm"
echo ">> Déposé : chaincode/verification/verifier.wasm ($(wc -c < "$DST/verifier.wasm") octets)"

cat <<'NOTE'

Étapes suivantes (dans chaincode/verification) :
  1. Ajouter wazero au module vendored :
       cd chaincode/verification
       go get github.com/tetratelabs/wazero
       go mod vendor
  2. Compiler :  go build ./...
  3. Câbler VerifyProof dans newVerificationContract() à la place de notWired{}.
Le test d'équivalence (go test) reste en SKIP tant que la brique A n'a pas
produit chaincode/verification/testdata/{receipt.bin,imageid.bin}.
NOTE
