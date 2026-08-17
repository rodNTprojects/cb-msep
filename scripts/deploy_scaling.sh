#!/usr/bin/env bash
# deploy_scaling.sh — variantes de verifycc pour l'étude de passage à l'échelle
# (P4) et la baseline ZK-Only (P2), sur le réseau 7-orgs.
#
# Membres  : Org1, Org2 (jamais endosseurs de verifycc).
# Non-membres disponibles : Org3, Org4, Org5, Org6, Org7 (2 -> 5).
#
# On déploie une DÉFINITION nommée par variante, avec sa propre politique
# d'endossement sur les n premiers non-membres. Le réseau reste statique ; c'est
# la POLITIQUE, pas l'appartenance au canal, qui fait varier n. Chaque définition
# a son propre namespace d'état (isolé des autres).
#
#   verifycc_zk1 : OutOf(1, Org3,Org4,Org5)     baseline ZK-Only (P2)
#   verifycc_n2  : OutOf(2, Org3,Org4)          n=2, t=majorite=2
#   verifycc_n3  : OutOf(2, Org3,Org4,Org5)     n=3, t=2   (= verifycc de base)
#   verifycc_n4  : OutOf(3, Org3..Org6)         n=4, t=3
#   verifycc_n5  : OutOf(3, Org3..Org7)         n=5, t=3
#
# Prérequis : réseau 7-orgs up + canal joint ; datacc déjà déployé (scripts/
# deploy.sh, pour TX1). Le matériel de binding (racines membres + image id) est
# rafraîchi ici — il ne dépend pas de n.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
CH=cbmsep
ORD=$(orderer_flags)

echo "== matériel de binding (indépendant de n) =="
bash scripts/refresh_binding_material.sh

echo "== vendor + package verifycc (une fois) =="
( cd chaincode/verification && go mod tidy && go mod vendor )
peer lifecycle chaincode package verifycc.tar.gz --path chaincode/verification --lang golang --label verifycc_scaled_1

echo "== install sur les 5 non-membres (Org3..Org7) =="
# Idempotent : « already successfully installed » (même package ID) n'est pas une
# erreur — on ne veut échouer que sur un vrai problème d'installation.
for n in 3 4 5 6 7; do setGlobals "$n"
  out=$(peer lifecycle chaincode install verifycc.tar.gz 2>&1) || true
  if echo "$out" | grep -qE 'Chaincode code package identifier|already successfully installed'; then
    echo "   org${n}: OK"
  else
    echo "$out"; echo "install KO org${n}"; exit 1
  fi
done
setGlobals 3
PID=$(peer lifecycle chaincode queryinstalled | sed -n 's/^Package ID: \(verifycc_scaled_1:[0-9a-f]*\).*/\1/p' | head -1)
echo "package id: $PID"

peer_flags_list() {  # emit --peerAddresses/--tlsRootCertFiles for an explicit org list
  local a="" j
  for j in "$@"; do
    local port=$((7051 + (j-1)*1000))
    local ca; ca=$(eval echo "\$ORG${j}_CA")
    a+=" --peerAddresses localhost:${port} --tlsRootCertFiles ${ca}"
  done
  echo "$a"
}

policy() {  # OutOf(t, Org<first>..Org<last>)   args: t first last
  local t="$1" first="$2" last="$3" ids="" j
  for j in $(seq "$first" "$last"); do ids+=",'Org${j}MSP.member'"; done
  echo "OutOf(${t}${ids})"
}

# Rejouable proprement : on INTERROGE l'état avant d'agir, au lieu d'avaler des
# erreurs. querycommitted -> déjà committé ? checkcommitreadiness -> quelles orgs
# ont déjà approuvé ? On n'approuve que ce qui manque.
deploy_variant() {  # name t first last
  local name="$1" t="$2" first="$3" last="$4"
  local pol; pol=$(policy "$t" "$first" "$last")
  echo; echo "== $name : $pol (endosseurs Org${first}..Org${last}) =="

  # 1) Déjà committé -> rien à faire.
  setGlobals 3
  if peer lifecycle chaincode querycommitted -C "$CH" --name "$name" >/dev/null 2>&1; then
    echo "   déjà committé, skip."; return
  fi

  # 2) État des approbations (une seule requête, lisible par toutes les orgs).
  local ready; ready=$(peer lifecycle chaincode checkcommitreadiness -C "$CH" --name "$name" \
    --version 1 --sequence 1 --signature-policy "$pol" --output json 2>/dev/null || echo '{}')

  approve_org() {  # n  withpkg(0/1)   approuve l'org $1 si pas déjà fait
    local n="$1" withpkg="$2"
    if echo "$ready" | grep -Eq "\"Org${n}MSP\"[[:space:]]*:[[:space:]]*true"; then
      echo "   Org${n}: déjà approuvé"; return
    fi
    setGlobals "$n"
    if [ "$withpkg" = "1" ]; then
      peer lifecycle chaincode approveformyorg $ORD -C "$CH" --name "$name" --version 1 --sequence 1 \
        --package-id "$PID" --signature-policy "$pol"
    else
      peer lifecycle chaincode approveformyorg $ORD -C "$CH" --name "$name" --version 1 --sequence 1 \
        --signature-policy "$pol"
    fi
    echo "   Org${n}: approuvé"
  }

  # Endosseurs (Org${first}..Org${last}) : AVEC package-id. Les autres : SANS.
  local j
  for j in $(seq "$first" "$last"); do approve_org "$j" 1; done
  for j in 1 2 3 4 5 6 7; do
    if [ "$j" -lt "$first" ] || [ "$j" -gt "$last" ]; then approve_org "$j" 0; fi
  done

  # 3) Commit : l'endossement du commit obéit à MAJORITY Endorsement du canal
  # (4 orgs sur 7), distinct de la politique OutOf(t,n) du chaincode. On inclut
  # les deux membres EN PLUS des endosseurs -> toujours >= 4 orgs.
  setGlobals "$first"
  peer lifecycle chaincode commit $ORD -C "$CH" --name "$name" --version 1 --sequence 1 \
    --signature-policy "$pol" $(peer_flags_list 1 2 $(seq "$first" "$last"))
  echo "   $name committed."
}

deploy_variant verifycc_zk1 1 3 5     # P2 : ZK-Only, un seul endosseur suffit
deploy_variant verifycc_n2   2 3 4     # n=2
deploy_variant verifycc_n3   2 3 5     # n=3
deploy_variant verifycc_n4   3 3 6     # n=4
deploy_variant verifycc_n5   3 3 7     # n=5

echo
echo "Variantes déployées. Harnais : bash scripts/test_phase7_scaling.sh"