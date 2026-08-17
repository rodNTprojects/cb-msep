#!/usr/bin/env bash
# deploy_datacc.sh — déploie UNIQUEMENT datacc (baseline Native PDC / TX1).
# Idempotent, commit à la majorité de lifecycle (4 orgs sur 7). Ne touche pas à
# verifycc. Nécessaire seulement pour test_phase7.sh (surcoût). Le scaling et le
# débit n'en ont pas besoin.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
CH=cbmsep
ORD=$(orderer_flags)
COLL=collections/collection_config.json
POL="OR('Org1MSP.member','Org2MSP.member')"

setGlobals 1
if peer lifecycle chaincode querycommitted -C "$CH" --name datacc >/dev/null 2>&1; then
  echo "datacc déjà committé — rien à faire."; exit 0
fi

echo "== package + install datacc (Org1, Org2) =="
( cd chaincode/data && go mod tidy && go mod vendor )
peer lifecycle chaincode package datacc.tar.gz --path chaincode/data --lang golang --label datacc_1
for n in 1 2; do setGlobals "$n"
  out=$(peer lifecycle chaincode install datacc.tar.gz 2>&1) || true
  echo "$out" | grep -qE 'Chaincode code package identifier|already successfully installed' \
    || { echo "$out"; echo "install datacc KO org$n"; exit 1; }
  echo "   org$n: OK"
done
setGlobals 1
PID=$(peer lifecycle chaincode queryinstalled | sed -n 's/^Package ID: \(datacc_1:[0-9a-f]*\).*/\1/p' | head -1)
echo "datacc: $PID"

ready=$(peer lifecycle chaincode checkcommitreadiness -C "$CH" --name datacc --version 1 --sequence 1 \
  --collections-config "$COLL" --signature-policy "$POL" --output json 2>/dev/null || echo '{}')
approve() {  # n withpkg
  local n="$1" wp="$2"
  if echo "$ready" | grep -Eq "\"Org${n}MSP\"[[:space:]]*:[[:space:]]*true"; then echo "   Org$n: déjà approuvé"; return; fi
  setGlobals "$n"
  if [ "$wp" = 1 ]; then
    peer lifecycle chaincode approveformyorg $ORD -C "$CH" --name datacc --version 1 --sequence 1 \
      --package-id "$PID" --collections-config "$COLL" --signature-policy "$POL"
  else
    peer lifecycle chaincode approveformyorg $ORD -C "$CH" --name datacc --version 1 --sequence 1 \
      --collections-config "$COLL" --signature-policy "$POL"
  fi
  echo "   Org$n: approuvé"
}
approve 1 1; approve 2 1
for n in 3 4 5 6 7; do approve "$n" 0; done      # -> majorité 4/7

setGlobals 1
peer lifecycle chaincode commit $ORD -C "$CH" --name datacc --version 1 --sequence 1 \
  --collections-config "$COLL" --signature-policy "$POL" \
  --peerAddresses localhost:7051  --tlsRootCertFiles "$ORG1_CA" \
  --peerAddresses localhost:8051  --tlsRootCertFiles "$ORG2_CA" \
  --peerAddresses localhost:9051  --tlsRootCertFiles "$ORG3_CA" \
  --peerAddresses localhost:10051 --tlsRootCertFiles "$ORG4_CA"
echo "datacc committed. Tu peux lancer : bash scripts/test_phase7.sh"
