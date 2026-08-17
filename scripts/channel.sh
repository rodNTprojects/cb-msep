#!/usr/bin/env bash
# Join all 7 peers to the channel. (Anchor peers are set in configtx.yaml at genesis;
# EXTERNALENDPOINT enables gossip. Run a manual anchor update later only if discovery needs it.)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
CH=cbmsep
for n in 1 2 3 4 5 6 7; do
  setGlobals "$n"
  echo "== peer0.org${n} joins ${CH} =="
  peer channel join -b channel-artifacts/${CH}.block
done
echo "All peers joined. Next: bash scripts/deploy.sh puis bash scripts/deploy_scaling.sh"
