#!/usr/bin/env bash
# analyze_inference.sh — fuite d'inférence par prédicat (A3). Calcul analytique
# sur les bornes du workload : k=max-min+1, entropie résiduelle log2(k), fuite
# log2(N)-log2(k). Lit workload/manifest.tsv.
# Usage : bash scripts/analyze_inference.sh [manifest.tsv] [--domain N]
set -uo pipefail
cd "$(dirname "$0")/.."
MAN="workload/manifest.tsv"; DOMAIN=""
while [ $# -gt 0 ]; do case "$1" in --domain) DOMAIN="$2"; shift 2;; *) MAN="$1"; shift;; esac; done
[ -f "$MAN" ] || { echo "manifeste introuvable: $MAN (lancer gen_workload.sh)"; exit 1; }

echo "== A3 — fuite d'inférence par prédicat =="; [ -n "$DOMAIN" ] && echo "   (domaine N=$DOMAIN)"; echo
awk -F'\t' -v DOM="$DOMAIN" '
function log2(x){return log(x)/log(2)}
NR==1{next}
{k=$4-$3+1; if(k<1)next; res=log2(k); K[++n]=k; MN[n]=$3; MX[n]=$4; KEY[n]=$1; RES[n]=res; sr+=res}
END{ if(n==0){print "  (aucun prédicat)"; exit}
  printf "  %-8s %-22s %12s %14s", "deed","[min,max]","k","entropy(b)";
  if(DOM!="")printf " %12s","leak(b)"; printf "\n";
  for(i=1;i<=n;i++){ printf "  %-8s [%d,%d]%*s %12d %14.3f", KEY[i],MN[i],MX[i], 12-length(MN[i])-length(MX[i]),"", K[i], RES[i];
    if(DOM!=""){l=log2(DOM+0)-RES[i]; if(l<0)l=0; printf " %12.3f",l} printf "\n" }
  printf "\n  mean residual entropy = %.3f bits over %d predicates\n", sr/n, n }' "$MAN"
