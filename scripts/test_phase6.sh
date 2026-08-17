#!/usr/bin/env bash
# Phase 6 - tests de securite de CB-MSEP (evidence pour les revendications).
# Chaque scenario est etiquete par la propriete testee et sa source.
# Prerequis : reseau up + deploye (Phase 4), brique A executee.
#
# Rappel honnete (taxonomie) : un test donne une EVIDENCE, pas une preuve.
# - crypto (soundness/ZK, infalsifiabilite sigma) : herite des preuves des
#   primitives ; ici on ne fait que du test NEGATIF (falsification -> rejet).
# - invariant no-private-read : analyse statique exhaustive (check_obliviousness.sh,
#   PDCHECKER en repli CI) + observation ledger.
# - seuil t-1 : la garantie vient de la politique d'endossement Fabric ; on
#   demontre qu'en-dessous du seuil, aucune attestation ne commite.

cd "$(dirname "$0")/.."
source scripts/env.sh

CH=cbmsep
C=a353c969452b888a5e3e1ba25e1bb783461898070de580e482cf8c8e8414fc53
FAKEC=0000000000000000000000000000000000000000000000000000000000000000
PUBIN=f049020000000000e093040000000000
WRONGPUBIN=0000000000000000e093040000000000     # min=0 au lieu de 150000
ORD=$(orderer_flags)
ORG1U=organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp
ORG2U=organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp
RECEIPT=chaincode/verification/testdata/receipt.bin

pass=0; fail=0
present() { if grep -qF "$2" <<<"$3"; then echo "  [PASS] $1"; pass=$((pass+1));
  else echo "  [FAIL] $1"; echo "     attendu ~ : $2"; echo "     obtenu   : $(echo "$3"|tr '\n' ' '|head -c 300)"; fail=$((fail+1)); fi; }
absent()  { if grep -qF "$2" <<<"$3"; then echo "  [FAIL] $1 (motif interdit present)"; fail=$((fail+1));
  else echo "  [PASS] $1"; pass=$((pass+1)); fi; }

echo ">> build des clients"
( cd client/attest && go build -o /tmp/attest . )        || exit 1
( cd client/sign_binding && go build -o /tmp/signbind . ) || exit 1
sigma() { /tmp/signbind "$1" "$C" "Org1MSP=$ORG1U" "Org2MSP=$ORG2U"; }
att() { /tmp/attest --key "$1" --commitment "$2" --sigma "$3" --publicin "$4" --receipt "$5" 2>&1; }

echo; echo "== SEC1 - Injection d'un commitment non autorise (Wang 2021) =="
bash scripts/submit.sh sec1 >/dev/null 2>&1
sigma sec1 > /tmp/sig_sec1.hex                     # sigma legitime sur le vrai C
OUT=$(att sec1 "$FAKEC" /tmp/sig_sec1.hex "$PUBIN" "$RECEIPT")   # mais on REVENDIQUE un faux C
present "commitment non signe par les membres -> binding rejected" "binding rejected" "$OUT"

echo; echo "== SEC2 - Infalsifiabilite de la preuve (soundness du STARK) =="
bash scripts/submit.sh sec2 >/dev/null 2>&1
sigma sec2 > /tmp/sig_sec2.hex
cp "$RECEIPT" /tmp/bad_receipt.bin
for off in 50 100 500 1000 5000; do printf '\xa5' | dd of=/tmp/bad_receipt.bin bs=1 seek=$off count=1 conv=notrunc 2>/dev/null; done
OUT=$(att sec2 "$C" /tmp/sig_sec2.hex "$PUBIN" /tmp/bad_receipt.bin)   # preuve corrompue
present "receipt corrompu -> proof rejected" "proof rejected" "$OUT"

echo; echo "== SEC3 - Liaison a l'enonce : bornes falsifiees (soudure journal<->publicIn) =="
bash scripts/submit.sh sec3 >/dev/null 2>&1
sigma sec3 > /tmp/sig_sec3.hex
OUT=$(att sec3 "$C" /tmp/sig_sec3.hex "$WRONGPUBIN" "$RECEIPT")        # bonnes preuve+sigma, mauvaises bornes
present "bornes min/max falsifiees -> proof rejected" "proof rejected" "$OUT"

echo; echo "== SEC4 - Seuil : en-dessous de OutOf(2,3), aucune attestation (CORE) =="
echo "   (on rend Org4 et Org5 injoignables : un seul non-membre ne suffit pas)"
docker stop peer0.org4.example.com peer0.org5.example.com >/dev/null 2>&1
bash scripts/submit.sh sec4 >/dev/null 2>&1
sigma sec4 > /tmp/sig_sec4.hex
OUT=$(att sec4 "$C" /tmp/sig_sec4.hex "$PUBIN" "$RECEIPT")
absent "1 seul endosseur -> pas d'Attest OK" "Attest OK" "$OUT"
echo "   redemarrage d'Org4 et Org5..."
docker start peer0.org4.example.com peer0.org5.example.com >/dev/null 2>&1
sleep 6

echo; echo "== SEC5 - Data-obliviousness (Chen 2024) =="
# (a) empirique : le non-membre (Org3, 7984) n'a AUCUNE base privee \$\$p ; le membre (Org1, 5984) oui.
NM=$(curl -s http://admin:adminpw@localhost:7984/_all_dbs | tr ',' '\n' | grep -i 'passet' || true)
M=$(curl -s http://admin:adminpw@localhost:5984/_all_dbs | tr ',' '\n' | grep -i 'passet' || true)
absent  "non-membre Org3 : pas de base privee en clair" "passet" "$NM"
present "membre Org1 : possede la base privee en clair" "passet" "$M"
# (b) statique EXHAUSTIF : CC_V n'appelle AUCUNE des 10 API private-data du shim.
#     (remplace l'ancien grep-proxy d'une seule fonction par l'enumeration complete.)
if bash scripts/check_obliviousness.sh > /tmp/oblivious.log 2>&1; then
  present "surface d'API privee vide (10/10 API absentes)" "obliviousness_ok=1" "$(cat /tmp/oblivious.log)"
else
  fail=$((fail+1)); echo "  [FAIL] check_obliviousness.sh a detecte un appel private-data :"
  grep -E '\[FAIL\]|VERDICT' /tmp/oblivious.log | sed 's/^/     /'
fi

echo
echo "======================================================"
echo "  Phase 6 : $pass PASS, $fail FAIL"
echo "======================================================"
echo "SEC6 - Inference (Islam/Dharani) : ANALYSE, pas pass/fail."
echo "  Pour le predicat 150000<=price<=300000, (C, vrai) revele price dans un"
echo "  intervalle de 150001 valeurs -> reduction d'entropie bornee par la"
echo "  granularite du predicat. A quantifier par predicat (taille de l'ensemble"
echo "  revele / entropie residuelle), au niveau PREDICAT, pas dans le circuit."
[ "$fail" -eq 0 ]
