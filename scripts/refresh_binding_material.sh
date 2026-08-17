#!/usr/bin/env bash
# Rafraîchit le matériel épinglé de CC_V AVANT le packaging :
#   - racines CA des membres -> chaincode/verification/member_roots/<MSPID>.pem
#   - image id du guest       -> chaincode/verification/expected_imageid.bin
#
# À lancer depuis la racine cbmsep-net, APRÈS cryptogen (up) et APRÈS la brique A
# (le host a écrit testdata/imageid.bin). Absorbe chaque regénération cryptogen
# (nouvelles racines) sans geler quoi que ce soit dans le code.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DST="$ROOT/chaincode/verification"
ORG_DIR="$ROOT/organizations/peerOrganizations"

mkdir -p "$DST/member_roots"

copy_root() {
  local org_domain="$1" mspid="$2" src
  src=$(ls "$ORG_DIR/$org_domain/msp/cacerts/"*.pem 2>/dev/null | head -n1 || true)
  [ -n "$src" ] || { echo "!! racine CA introuvable pour $mspid ($org_domain)"; exit 1; }
  cp "$src" "$DST/member_roots/$mspid.pem"
  echo ">> member_roots/$mspid.pem  <-  $src"
}

# Membres = Org1, Org2 (adapte si ta topologie diffère).
copy_root org1.example.com Org1MSP
copy_root org2.example.com Org2MSP

if [ -f "$DST/testdata/imageid.bin" ]; then
  cp "$DST/testdata/imageid.bin" "$DST/expected_imageid.bin"
  echo ">> expected_imageid.bin  <-  testdata/imageid.bin ($(wc -c < "$DST/expected_imageid.bin") octets)"
else
  echo "!! testdata/imageid.bin absent — lance d'abord la brique A (cd zk/prover && cargo run --release --bin host)"
  exit 1
fi

echo
echo "OK. Ensuite, dans chaincode/verification :"
echo "   go build ./...        # doit compiler (member_roots + expected_imageid + verifier.wasm présents)"
echo "   puis package/deploy CC_V (le matériel épinglé part avec le //go:embed)."
