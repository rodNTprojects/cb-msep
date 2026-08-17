#!/usr/bin/env bash
# Phase-2 smoke test: TX1 SubmitData with a sample D (structured branch), then read the record.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
CH=cbmsep
KEY="${1:-asset1}"
D='price=250000;parcel=AB-12;partyA=Alice;partyB=Bob'
ORD=$(orderer_flags)

setGlobals 1   # a member submits
peer chaincode invoke $ORD -C "$CH" -n datacc \
  --peerAddresses localhost:7051 --tlsRootCertFiles "$ORG1_CA" \
  --peerAddresses localhost:8051 --tlsRootCertFiles "$ORG2_CA" \
  -c '{"function":"SubmitData","Args":["'"$KEY"'","range-price"]}' \
  --transient "{\"data\":\"$(printf '%s' "$D" | base64 | tr -d '\n')\"}"

sleep 2
peer chaincode query -C "$CH" -n datacc -c '{"function":"ReadRecord","Args":["'"$KEY"'"]}'
echo
echo "Cleartext D lives only on Org1/Org2 CouchDB (5984/6984); Org3/4/5 hold only hashes."
echo "verifycc.Attest currently returns 'sigma verifier not wired' — expected until Phases 3-4."
