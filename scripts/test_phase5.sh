#!/usr/bin/env bash
# Phase 5 - tests fonctionnels reproductibles de CB-MSEP.
# Prérequis : réseau up + déployé (datacc+verifycc Phase 4), brique A exécutée
# (chaincode/verification/testdata/receipt.bin + imageid.bin présents).
# Chaque scénario affiche attendu / obtenu et un verdict PASS/FAIL.

cd "$(dirname "$0")/.."
source scripts/env.sh

CH=cbmsep
C=a353c969452b888a5e3e1ba25e1bb783461898070de580e482cf8c8e8414fc53
PUBIN=f049020000000000e093040000000000
ORD=$(orderer_flags)
ORG1U=organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp
ORG2U=organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp

# Identifiant de run : rend la suite REJOUABLE sans re-déployer. Sans lui, les
# clés fixes (p5happy...) collisionnent avec un passage précédent -> "already
# attested" au lieu du chemin heureux.
RUN=$(date +%s)
KH="p5happy_$RUN"     # S1 + S3 (rejeu idempotent) partagent cette clé
KO="p5other_$RUN"     # S2 : clé pour laquelle on signe le MAUVAIS sigma
KN="p5nobind_$RUN"    # S2 : clé qu'on tente d'attester avec ce sigma
KC="p5cancel_$RUN"    # S4
KM="p5mvcc_$RUN"      # S5

pass=0; fail=0
check() { # desc, expected_substr, actual
  if grep -qF "$2" <<<"$3"; then
    echo "  [PASS] $1"; pass=$((pass+1))
  else
    echo "  [FAIL] $1"; echo "     attendu ~ : $2"
    echo "     obtenu   : $(echo "$3" | tr '\n' ' ' | head -c 320)"; fail=$((fail+1))
  fi
}

echo ">> build des clients"
( cd client/attest && go build -o /tmp/attest . )       || { echo "build attest KO"; exit 1; }
( cd client/sign_binding && go build -o /tmp/signbind . ) || { echo "build signbind KO"; exit 1; }

sigma() { /tmp/signbind "$1" "$C" "Org1MSP=$ORG1U" "Org2MSP=$ORG2U"; }
attest() { /tmp/attest --key "$1" --commitment "$C" --publicin "$PUBIN" --sigma "$2" 2>&1; }

echo; echo "== S1 - chemin heureux (pending -> attested) =="
bash scripts/submit.sh "$KH" >/dev/null 2>&1
sigma "$KH" > /tmp/sig_happy.hex
OUT=$(attest "$KH" /tmp/sig_happy.hex)
check "attestation acceptée"      "Attest OK"             "$OUT"
check "statut attested"           '"status":"attested"'  "$OUT"

echo; echo "== S2 - précondition : binding invalide -> échec propre =="
bash scripts/submit.sh "$KN" >/dev/null 2>&1
sigma "$KO" > /tmp/sig_wrong.hex          # sigma signé pour une AUTRE clé
OUT=$(attest "$KN" /tmp/sig_wrong.hex)
check "binding rejeté (sigma ne couvre pas la clé)" "binding rejected" "$OUT"

echo; echo "== S3 - rejeu idempotent (re-Attest d'une clé déjà attestée) =="
OUT=$(attest "$KH" /tmp/sig_happy.hex)
check "déjà attesté, pas de double écriture" "already attested" "$OUT"

echo; echo "== S4 - Cancel (pending -> cancelled) + garde =="
bash scripts/submit.sh "$KC" >/dev/null 2>&1
setGlobals 1
peer chaincode invoke $ORD -C "$CH" -n datacc --waitForEvent \
  --peerAddresses localhost:7051 --tlsRootCertFiles "$ORG1_CA" \
  --peerAddresses localhost:8051 --tlsRootCertFiles "$ORG2_CA" \
  -c '{"function":"Cancel","Args":["'"$KC"'"]}' >/dev/null 2>&1
OUT=$(peer chaincode query -C "$CH" -n datacc -c '{"function":"ReadRecord","Args":["'"$KC"'"]}' 2>&1)
check "statut cancelled" '"status":"cancelled"' "$OUT"
OUT=$(peer chaincode invoke $ORD -C "$CH" -n datacc --waitForEvent \
  --peerAddresses localhost:7051 --tlsRootCertFiles "$ORG1_CA" \
  --peerAddresses localhost:8051 --tlsRootCertFiles "$ORG2_CA" \
  -c '{"function":"Cancel","Args":["'"$KC"'"]}' 2>&1)
check "garde : re-cancel refusé" "not pending" "$OUT"

echo; echo "== S5 - concurrence MVCC : deux Attest simultanés, une seule écriture =="
# Deux transactions Attest sur LA MÊME clé, lancées en parallèle. Elles lisent
# toutes deux l'état pending (version v0), endossent, puis soumettent. Fabric
# valide en série : la première commite (v0->v1), la seconde échoue en
# MVCC_READ_CONFLICT (lecture v0 périmée) OU, si l'ordonnancement les sérialise,
# est rejetée par la garde applicative "already attested". Dans les deux cas :
# exactement UNE attestation, jamais de double écriture.
bash scripts/submit.sh "$KM" >/dev/null 2>&1
sigma "$KM" > /tmp/sig_mvcc.hex
attest "$KM" /tmp/sig_mvcc.hex > /tmp/mvcc_a.log 2>&1 &
PA=$!
attest "$KM" /tmp/sig_mvcc.hex > /tmp/mvcc_b.log 2>&1 &
PB=$!
wait "$PA"; wait "$PB"
BOTH=$(cat /tmp/mvcc_a.log /tmp/mvcc_b.log)
NOK=$(grep -cF "Attest OK" /tmp/mvcc_a.log /tmp/mvcc_b.log | awk -F: '{s+=$2} END{print s}')
if [ "$NOK" -eq 1 ]; then
  echo "  [PASS] exactement un commit (Attest OK compté = 1)"; pass=$((pass+1))
else
  echo "  [FAIL] Attest OK compté = $NOK (attendu 1)"
  echo "     A: $(tr '\n' ' ' < /tmp/mvcc_a.log | head -c 200)"
  echo "     B: $(tr '\n' ' ' < /tmp/mvcc_b.log | head -c 200)"; fail=$((fail+1))
fi
# Le perdant motive son rejet : conflit MVCC (concurrence réelle) ou garde
# applicative (sérialisation). L'un ou l'autre est un rejet légitime.
if grep -qiE 'MVCC_READ_CONFLICT|already attested|conflict' <<<"$BOTH"; then
  echo "  [PASS] le perdant est rejeté (MVCC_READ_CONFLICT ou already attested)"; pass=$((pass+1))
else
  echo "  [FAIL] motif de rejet du perdant introuvable"
  echo "     obtenu : $(echo "$BOTH" | tr '\n' ' ' | head -c 300)"; fail=$((fail+1))
fi
# Vérité au grand livre : un seul enregistrement, attesté. verifycc n'est
# installé que sur les NON-membres -> interroger depuis Org3 (setGlobals 3),
# sinon "chaincode is not installed" si l'env est resté sur un membre.
setGlobals 3
OUT=$(peer chaincode query -C "$CH" -n verifycc -c '{"function":"ReadAttestation","Args":["'"$KM"'"]}' 2>&1)
check "état final : une attestation unique" '"status":"attested"' "$OUT"

echo
echo "======================================================"
echo "  Phase 5 : $pass PASS, $fail FAIL"
echo "======================================================"
[ "$fail" -eq 0 ]
