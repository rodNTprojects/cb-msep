#!/usr/bin/env bash
# test_phase7.sh — coût de l'obliviousness (harnais léger, progression en direct).
# CLÉS UNIQUES PAR RUN (suffixe $RUN) : on mesure de vraies transactions, jamais
# le rejet idempotent d'une clé déjà vue.
#   TX1 Native PDC (datacc) | PRV génération de preuve | TX2 Full CB-MSEP (verifycc_n3)
# Prérequis : réseau déployé (datacc + verifycc_n3) ; brique A jouée.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

N=${1:-15}
PN=${2:-3}
CH=cbmsep
CC_V=verifycc_n3
C=a353c969452b888a5e3e1ba25e1bb783461898070de580e482cf8c8e8414fc53
PUBIN=f049020000000000e093040000000000
ORD=$(orderer_flags)
ORG1U=organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp
ORG2U=organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp
RECEIPT=chaincode/verification/testdata/receipt.bin
D='price=250000;parcel=AB-12;partyA=Alice;partyB=Bob'
RUN=$(date +%s)
OUTCSV=data/phase7_overhead_results.csv
mkdir -p data

now() { date +%s%3N; }
stat_line() { awk 'NR==1{mn=mx=$1} {s+=$1; ss+=$1*$1; n++; if($1<mn)mn=$1; if($1>mx)mx=$1}
  END{ if(n==0){print "0 0 0 0"; exit} m=s/n; v=ss/n-m*m; if(v<0)v=0;
       printf "%.0f %.0f %.0f %.0f", m, sqrt(v), mn, mx }'; }

echo ">> build clients + host"
( cd client/attest && go build -o /tmp/attest . )        || { echo "build attest KO"; exit 1; }
( cd client/sign_binding && go build -o /tmp/signbind . ) || { echo "build signbind KO"; exit 1; }
( cd zk/prover && cargo build --release --bin host ) >/dev/null 2>&1 || echo "  (host déjà compilé)"
sig() { /tmp/signbind "$1" "$C" "Org1MSP=$ORG1U" "Org2MSP=$ORG2U"; }
att() { /tmp/attest --chaincode "$CC_V" --key "$1" --commitment "$C" --publicin "$PUBIN" --sigma "$2"; }

echo "== préflight =="
[ -s "$RECEIPT" ] || { echo "  ÉCHEC : $RECEIPT absent. Lance la brique A (cargo run --release --bin host)."; exit 1; }
setGlobals 3
for cc in datacc "$CC_V"; do
  if ! peer lifecycle chaincode querycommitted -C "$CH" --name "$cc" >/tmp/qc.out 2>&1; then
    echo "  ÉCHEC : chaincode '$cc' non committé. Détail :"; sed 's/^/    /' /tmp/qc.out
    [ "$cc" = datacc ] && echo "  Déploie le baseline : bash scripts/deploy_datacc.sh" \
                       || echo "  Déploie : bash scripts/deploy_phase7.sh"
    exit 1
  fi
done
echo "  chaincodes OK (datacc, $CC_V)"
PK="pre_${RUN}"; sig "$PK" > /tmp/sig_pre.hex 2>/tmp/sig_pre.err
[ -s /tmp/sig_pre.hex ] || { echo "  ÉCHEC : signbind vide. Détail :"; sed 's/^/    /' /tmp/sig_pre.err; exit 1; }
att "$PK" /tmp/sig_pre.hex >/tmp/pre.out 2>&1 || true
if ! grep -qE "Attest OK|already attested" /tmp/pre.out; then
  echo "  ÉCHEC : l'attestation de test n'a pas abouti. Sortie complète :"
  sed 's/^/    /' /tmp/pre.out
  echo "  (réseau up ? endosseurs joignables ? verifycc_n3 démarré ?)"; exit 1
fi
echo "  OK, la chaîne d'attestation répond."

echo "label,mean_ms,sd_ms,min_ms,max_ms,reps" > "$OUTCSV"
echo "  taille receipt : $(wc -c < "$RECEIPT") octets"

echo; echo "== PRV : génération de preuve x$PN (lent) =="
: > /tmp/prv.txt
for i in $(seq 1 "$PN"); do
  echo "   preuve $i/$PN en cours..."
  s=$(now); ( cd zk/prover && ./target/release/host ) >/dev/null 2>&1 || { echo "   host KO"; exit 1; }
  e=$(now); d=$((e - s)); echo "$d" >> /tmp/prv.txt; echo "      -> $d ms"
done
read -r PRV psd pmn pmx < <(stat_line < /tmp/prv.txt)
echo "   PRV moyenne=$PRV ms"
echo "PRV,$PRV,$psd,$pmn,$pmx,$PN" >> "$OUTCSV"

echo; echo "== TX1 : Native PDC (datacc SubmitData) x$N =="
setGlobals 1
: > /tmp/tx1.txt
for i in $(seq 1 "$N"); do
  s=$(now)
  peer chaincode invoke $ORD -C "$CH" -n datacc --waitForEvent \
    --peerAddresses localhost:7051 --tlsRootCertFiles "$ORG1_CA" \
    --peerAddresses localhost:8051 --tlsRootCertFiles "$ORG2_CA" \
    -c '{"function":"SubmitData","Args":["p7n'"${RUN}_$i"'","range-price"]}' \
    --transient "{\"data\":\"$(printf '%s' "$D" | base64 | tr -d '\n')\"}" >/dev/null 2>&1
  e=$(now); echo $((e - s)) >> /tmp/tx1.txt; printf '   TX1 %d/%d\r' "$i" "$N"
done; echo
read -r TX1 sd1 mn1 mx1 < <(stat_line < /tmp/tx1.txt)
echo "   TX1 moyenne=$TX1 ms"
echo "TX1_NativePDC,$TX1,$sd1,$mn1,$mx1,$N" >> "$OUTCSV"

echo; echo "== TX2 : Full CB-MSEP (verifycc_n3 Attest) x$N =="
for i in $(seq 1 "$N"); do sig "p7f_${RUN}_$i" > "/tmp/sig_p7f$i.hex" 2>/dev/null; done
: > /tmp/tx2.txt
for i in $(seq 1 "$N"); do
  s=$(now); att "p7f_${RUN}_$i" "/tmp/sig_p7f$i.hex" >/dev/null 2>&1; e=$(now)
  echo $((e - s)) >> /tmp/tx2.txt; printf '   TX2 %d/%d\r' "$i" "$N"
done; echo
read -r TX2 sd2 mn2 mx2 < <(stat_line < /tmp/tx2.txt)
echo "   TX2 moyenne=$TX2 ms"
echo "TX2_FullCBMSEP,$TX2,$sd2,$mn2,$mx2,$N" >> "$OUTCSV"

echo; echo "== Surcoût de l'obliviousness vs Native PDC =="
awk -v t1="$TX1" -v t2="$TX2" -v prv="$PRV" 'BEGIN{
  over = prv + (t2 - t1); pct = (t1>0)? 100.0*over/t1 : 0;
  printf "  Native PDC (TX1)          = %d ms\n", t1;
  printf "  Full CB-MSEP (PRV+TX2)    = %d ms\n", prv + t2;
  printf "  surcout (PRV + TX2 - TX1) = %d ms  (+%.0f%% vs Native PDC)\n", over, pct;
}'
echo; echo "CSV écrit : $OUTCSV"
echo "Graphe    : python3 scripts/plot_overhead.py"
