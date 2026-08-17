#!/usr/bin/env bash
# Bring up the 5-org network and join the orderer to the channel.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
CH=cbmsep

echo "== 1. crypto material =="
[ -d organizations ] && rm -rf organizations
cryptogen generate --config=crypto-config.yaml --output=organizations

echo "== 2. channel genesis block =="
mkdir -p channel-artifacts
gen_cfg
configtxgen -profile CBMSEPChannel -channelID "$CH" -outputBlock channel-artifacts/${CH}.block

echo "== 3. docker compose up =="
docker compose -f compose/compose-net.yaml up -d
sleep 4

echo "== 4. orderer joins the channel =="
osnadmin channel join --channelID "$CH" --config-block channel-artifacts/${CH}.block \
  -o localhost:7053 --ca-file "$ORDERER_CA" \
  --client-cert "$ORDERER_ADMIN_CERT" --client-key "$ORDERER_ADMIN_KEY"

echo "Network up. Next: bash scripts/channel.sh"
