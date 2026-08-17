#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose -f compose/compose-net.yaml down -v
# remove chaincode containers/images built by the peer
docker rm -f $(docker ps -aq --filter "name=dev-peer") 2>/dev/null || true
docker rmi -f $(docker images -q "dev-peer*") 2>/dev/null || true
rm -rf organizations channel-artifacts *.tar.gz
echo "Network down and cleaned."
