#!/usr/bin/env bash
# test_phase7_throughput.sh — débit/latence sous concurrence, TROIS configurations
# (façon TrustFabric) : Native (datacc), ZK-Only (verifycc_zk1), Full (verifycc_n3).
#
# RIGUEUR :
#  - on ne compte dans la latence QUE les transactions RÉUSSIES (un échec rapide
#    sous contention ne doit pas passer pour une faible latence) ;
#  - le débit = réussites / temps_de_lot ;
#  - on rapporte le TAUX DE SUCCÈS (une chute sous concurrence est un résultat) ;
#  - chauffe par configuration (pas de biais d'ordre à froid) ;
#  - REPS répétitions par (config, palier), moyenne ± écart-type, clés uniques.
#
# Usage : [REPS=5] bash scripts/test_phase7_throughput.sh [C1 C2 ...]
# Prérequis : datacc + verifycc_zk1 + verifycc_n3 déployés ; brique A jouée.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

C=a353c969452b888a5e3e1ba25e1bb783461898070de580e482cf8c8e8414fc53
PUBIN=f049020000000000e093040000000000
ORD=$(orderer_flags)
ORG1U=organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp
ORG2U=organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp
D='price=250000;parcel=AB-12;partyA=Alice;partyB=Bob'
B64D=$(printf '%s' "$D" | base64 | tr -d '\n')
LEVELS=(${*:-1 2 4 8 16})
REPS=${REPS:-5}
RUN=$(date +%s)
OUTCSV=data/phase7_throughput_results.csv
mkdir -p data /tmp/tput
now() { date +%s%3N; }
mean_sd() { awk '{s+=$1;ss+=$1*$1;n++} END{if(n==0){print "0 0";exit} m=s/n;v=ss/n-m*m;if(v<0)v=0;printf "%.2f %.2f",m,sqrt(v)}'; }

echo ">> build clients"
( cd client/attest && go build -o /tmp/attest . )        || { echo "build attest KO"; exit 1; }
( cd client/sign_binding && go build -o /tmp/signbind . ) || { echo "build signbind KO"; exit 1; }
sig() { /tmp/signbind "$1" "$C" "Org1MSP=$ORG1U" "Org2MSP=$ORG2U"; }
att() { /tmp/attest --chaincode "$1" --key "$2" --commitment "$C" --publicin "$PUBIN" --sigma "$3"; }

echo "== préflight =="
RECEIPT=chaincode/verification/testdata/receipt.bin
[ -s "$RECEIPT" ] || { echo "  ÉCHEC : $RECEIPT absent. Lance la brique A."; exit 1; }
setGlobals 3
for cc in datacc verifycc_zk1 verifycc_n3; do
  peer lifecycle chaincode querycommitted -C cbmsep --name "$cc" >/dev/null 2>&1 \
    || { echo "  ÉCHEC : '$cc' non committé. (deploy_phase7.sh / deploy_datacc.sh)"; exit 1; }
done
echo "  datacc, verifycc_zk1, verifycc_n3 OK."
setGlobals 1   # contexte membre pour les invokes Native

LATF=/tmp/tput/lat.txt
# run_batch : lance Cc transactions en parallèle. N'enregistre la latence QUE si la
# transaction a réussi. Renvoie : "batch_ms  reussites".
run_batch() {  # kind chaincode Cc rep
  local kind="$1" cc="$2" Cc="$3" rep="$4" key
  : > "$LATF"
  local keys=()
  for k in $(seq 1 "$Cc"); do
    # clé unique : run + config + PALIER + rep + index (le palier est essentiel,
    # sinon les paliers qui doublent réutilisent les clés déjà attestées -> la
    # garde idempotente de verifycc rejette la moitié des tx).
    key="tp_${RUN}_${cc}_c${Cc}_${rep}_${k}"; keys+=("$key")
    [ "$kind" = attest ] && sig "$key" > "/tmp/tput/${key}.hex" 2>/dev/null
  done
  local bs; bs=$(now)
  for key in "${keys[@]}"; do
    if [ "$kind" = native ]; then
      ( s=$(now)
        if peer chaincode invoke $ORD -C cbmsep -n datacc --waitForEvent \
             --peerAddresses localhost:7051 --tlsRootCertFiles "$ORG1_CA" \
             --peerAddresses localhost:8051 --tlsRootCertFiles "$ORG2_CA" \
             -c '{"function":"SubmitData","Args":["'"$key"'","range-price"]}' \
             --transient "{\"data\":\"$B64D\"}" >/dev/null 2>&1
        then e=$(now); echo $((e-s)) >> "$LATF"; fi ) &
    else
      ( s=$(now)
        if att "$cc" "$key" "/tmp/tput/${key}.hex" >/dev/null 2>&1
        then e=$(now); echo $((e-s)) >> "$LATF"; fi ) &
    fi
  done
  wait
  local be; be=$(now)
  echo "$((be-bs)) $(wc -l < "$LATF")"
}

CONFIGS=("Native native datacc" "ZK-Only attest verifycc_zk1" "Full attest verifycc_n3")

echo "config,concurrency,tps_mean,tps_sd,lat_mean_ms,lat_sd_ms,ok_rate,reps" > "$OUTCSV"
echo; echo "== Débit/latence sous concurrence, $REPS répétitions/palier =="
for cfg in "${CONFIGS[@]}"; do
  read -r LABEL KIND CC <<<"$cfg"
  echo "-- config $LABEL ($CC) --"
  # chauffe de CETTE config (2 tx séquentielles, hors mesure)
  run_batch "$KIND" "$CC" 1 w1 >/dev/null; run_batch "$KIND" "$CC" 1 w2 >/dev/null
  for Cc in "${LEVELS[@]}"; do
    : > /tmp/tput/tps_all.txt; : > /tmp/tput/lat_all.txt; tot_ok=0; tot_att=0
    for rep in $(seq 1 "$REPS"); do
      read -r batch ok < <(run_batch "$KIND" "$CC" "$Cc" "$rep")
      awk -v k="$ok" -v b="$batch" 'BEGIN{if(b>0)printf "%.4f\n",1000.0*k/b; else print 0}' >> /tmp/tput/tps_all.txt
      cat "$LATF" >> /tmp/tput/lat_all.txt
      tot_ok=$((tot_ok+ok)); tot_att=$((tot_att+Cc))
      printf '   C=%s rep %s/%s (lot %s ms, ok %s/%s)\r' "$Cc" "$rep" "$REPS" "$batch" "$ok" "$Cc"
    done
    read -r TPSM TPSSD < <(mean_sd < /tmp/tput/tps_all.txt)
    read -r LATM LATSD < <(mean_sd < /tmp/tput/lat_all.txt)
    OKR=$(awk -v a="$tot_att" -v o="$tot_ok" 'BEGIN{if(a>0)printf "%.2f",o/a; else print 0}')
    echo "   C=$Cc  débit=$TPSM ± $TPSSD tx/s   latence=$LATM ± $LATSD ms   succès=$OKR      "
    echo "$LABEL,$Cc,$TPSM,$TPSSD,$LATM,$LATSD,$OKR,$REPS" >> "$OUTCSV"
  done
done
echo; echo "CSV écrit : $OUTCSV"
echo "Graphe    : python3 scripts/plot_throughput.py"
echo "NB : latence = transactions RÉUSSIES uniquement ; ok_rate < 1 = saturation réelle."
