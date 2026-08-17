#!/usr/bin/env bash
# test_phase7_scaling.sh — latence d'attestation TX2 vs nombre de non-membres n.
# Clés uniques par run ; tour de chauffe par variante ; CSV -> plot_scaling.py.
# Prérequis : réseau 7-orgs déployé (deploy_phase7.sh) + brique A jouée.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

N=${1:-15}
C=a353c969452b888a5e3e1ba25e1bb783461898070de580e482cf8c8e8414fc53
PUBIN=f049020000000000e093040000000000
ORG1U=organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp
ORG2U=organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp
RUN=$(date +%s)
OUTCSV=data/phase7_scaling_results.csv
mkdir -p data
now() { date +%s%3N; }

echo ">> build clients"
( cd client/attest && go build -o /tmp/attest . )        || { echo "build attest KO"; exit 1; }
( cd client/sign_binding && go build -o /tmp/signbind . ) || { echo "build signbind KO"; exit 1; }
sig() { /tmp/signbind "$1" "$C" "Org1MSP=$ORG1U" "Org2MSP=$ORG2U"; }
att() { /tmp/attest --chaincode "$1" --key "$2" --commitment "$C" --publicin "$PUBIN" --sigma "$3"; }

# variante : label ccname n t
VARIANTS=(
  "ZK-Only verifycc_zk1 3 1"
  "n=2 verifycc_n2 2 2"
  "n=3 verifycc_n3 3 2"
  "n=4 verifycc_n4 4 3"
  "n=5 verifycc_n5 5 3"
)

echo "label,n,t,mean_ms,sd_ms,min_ms,max_ms,reps" > "$OUTCSV"
echo; echo "== Latence d'attestation TX2 par variante (x$N, +1 chauffe) =="
for v in "${VARIANTS[@]}"; do
  read -r LABEL CC NN TT <<<"$v"
  echo "-- $LABEL : $CC (n=$NN, t=$TT) --"
  sig "warm_${RUN}_${CC}" > "/tmp/sw_${CC}.hex" 2>/dev/null
  att "$CC" "warm_${RUN}_${CC}" "/tmp/sw_${CC}.hex" >/dev/null 2>&1 || true
  for i in $(seq 1 "$N"); do sig "s_${RUN}_${CC}_${i}" > "/tmp/ss_${CC}_${i}.hex" 2>/dev/null; done
  : > /tmp/scal.txt
  for i in $(seq 1 "$N"); do
    s=$(now); att "$CC" "s_${RUN}_${CC}_${i}" "/tmp/ss_${CC}_${i}.hex" >/dev/null 2>&1; e=$(now)
    echo $((e - s)) >> /tmp/scal.txt; printf '   %d/%d\r' "$i" "$N"
  done; echo
  read -r M SD MN MX < <(awk 'NR==1{mn=mx=$1}{s+=$1;ss+=$1*$1;n++;if($1<mn)mn=$1;if($1>mx)mx=$1}
    END{m=s/n;v=ss/n-m*m;if(v<0)v=0;printf "%.0f %.0f %.0f %.0f",m,sqrt(v),mn,mx}' /tmp/scal.txt)
  echo "   -> moyenne=$M ± $SD ms  (min=$MN max=$MX)"
  echo "$LABEL,$NN,$TT,$M,$SD,$MN,$MX,$N" >> "$OUTCSV"
done
echo; echo "CSV : $OUTCSV  ;  graphe : python3 scripts/plot_scaling.py"
