#!/usr/bin/env bash
# Source from the project root:  source scripts/env.sh
# Requires the Fabric binaries + config. Point FABRIC_INSTALL at your Fabric install
# (the folder that contains bin/ and config/ — e.g. your fabric-samples, kept OUTSIDE this project).
export FABRIC_INSTALL="${FABRIC_INSTALL:-$HOME/fabric-samples}"
export PATH="$FABRIC_INSTALL/bin:$PATH"

export ORDERER_CA="$PWD/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt"
export ORDERER_ADMIN_CERT="$PWD/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.crt"
export ORDERER_ADMIN_KEY="$PWD/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.key"
# 7 orgs : Org1/Org2 membres, Org3..Org7 non-membres (scaling 2->5 non-membres).
for n in 1 2 3 4 5 6 7; do
  export "ORG${n}_CA=$PWD/organizations/peerOrganizations/org${n}.example.com/peers/peer0.org${n}.example.com/tls/ca.crt"
done

# peer CLI needs core.yaml (from the Fabric install); configtxgen needs configtx.yaml (project root).
peer_cfg()  { export FABRIC_CFG_PATH="$FABRIC_INSTALL/config"; }
gen_cfg()   { export FABRIC_CFG_PATH="$PWD"; }

setGlobals() {
  local n=$1
  peer_cfg
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_LOCALMSPID="Org${n}MSP"
  local base="$PWD/organizations/peerOrganizations/org${n}.example.com"
  export CORE_PEER_TLS_ROOTCERT_FILE="${base}/peers/peer0.org${n}.example.com/tls/ca.crt"
  export CORE_PEER_MSPCONFIGPATH="${base}/users/Admin@org${n}.example.com/msp"
  export CORE_PEER_ADDRESS="localhost:$((7051 + (n-1)*1000))"
}

orderer_flags() {
  echo "-o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA"
}
