#!/usr/bin/env bash
# Per-role deployment: CC_D (datacc) on members Org1/Org2; CC_V (verifycc) on non-members Org3/4/5.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
CH=cbmsep
COLL=collections/collection_config.json
ORD=$(orderer_flags)
CC_D_POL="OR('Org1MSP.member','Org2MSP.member')"
CC_V_POL="OutOf(2,'Org3MSP.member','Org4MSP.member','Org5MSP.member')"

echo "== vendor chaincode deps =="
( cd chaincode/data && go mod tidy && go mod vendor )
( cd chaincode/verification && go mod tidy && go mod vendor )

pkgid() { peer lifecycle chaincode queryinstalled | sed -n "s/^Package ID: \($1:[0-9a-f]*\).*/\1/p" | head -1; }

echo "== CC_D (datacc): members only =="
peer lifecycle chaincode package datacc.tar.gz --path chaincode/data --lang golang --label datacc_1
for n in 1 2; do setGlobals "$n"; peer lifecycle chaincode install datacc.tar.gz || true; done
setGlobals 1; PID_D=$(pkgid datacc_1); echo "datacc: $PID_D"
for n in 1 2; do setGlobals "$n"
  peer lifecycle chaincode approveformyorg $ORD -C "$CH" --name datacc --version 1 --sequence 1 \
    --package-id "$PID_D" --collections-config "$COLL" --signature-policy "$CC_D_POL"
done
setGlobals 3   # a non-member approves the definition WITHOUT installing -> 3/5 majority
peer lifecycle chaincode approveformyorg $ORD -C "$CH" --name datacc --version 1 --sequence 1 \
  --collections-config "$COLL" --signature-policy "$CC_D_POL"
setGlobals 1
peer lifecycle chaincode commit $ORD -C "$CH" --name datacc --version 1 --sequence 1 \
  --collections-config "$COLL" --signature-policy "$CC_D_POL" \
  --peerAddresses localhost:7051 --tlsRootCertFiles "$ORG1_CA" \
  --peerAddresses localhost:8051 --tlsRootCertFiles "$ORG2_CA" \
  --peerAddresses localhost:9051 --tlsRootCertFiles "$ORG3_CA"

echo "== CC_V (verifycc): non-members only, OutOf(2,3) =="
peer lifecycle chaincode package verifycc.tar.gz --path chaincode/verification --lang golang --label verifycc_1
for n in 3 4 5; do setGlobals "$n"; peer lifecycle chaincode install verifycc.tar.gz || true; done
setGlobals 3; PID_V=$(pkgid verifycc_1); echo "verifycc: $PID_V"
for n in 3 4 5; do setGlobals "$n"
  peer lifecycle chaincode approveformyorg $ORD -C "$CH" --name verifycc --version 1 --sequence 1 \
    --package-id "$PID_V" --signature-policy "$CC_V_POL"
done
setGlobals 1   # a member approves the definition WITHOUT installing -> majority
peer lifecycle chaincode approveformyorg $ORD -C "$CH" --name verifycc --version 1 --sequence 1 \
  --signature-policy "$CC_V_POL"
setGlobals 3
peer lifecycle chaincode commit $ORD -C "$CH" --name verifycc --version 1 --sequence 1 \
  --signature-policy "$CC_V_POL" \
  --peerAddresses localhost:9051  --tlsRootCertFiles "$ORG3_CA" \
  --peerAddresses localhost:10051 --tlsRootCertFiles "$ORG4_CA" \
  --peerAddresses localhost:11051 --tlsRootCertFiles "$ORG5_CA"

echo "Deployed. datacc on Org1/Org2 (members); verifycc on Org3/4/5 (non-members, OutOf(2,3))."
